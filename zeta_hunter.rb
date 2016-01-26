require_relative File.join "lib", "lib_helper.rb"

include Const
include Assert
include Utils

Process.extend CoreExtensions::Process
Time.extend CoreExtensions::Time
File.extend CoreExtensions::File

logger = Logger.new STDERR

this_dir = File.dirname(__FILE__)

opts = {
  inaln: TEST_ALN,
  outdir: TEST_OUTDIR,
  threads: 2,
  db_otu_info: DB_OTU_INFO,
  mask: MASK,
  db_seqs: DB_SEQS,
}

######################################################################
# FOR TEST ONLY -- remove outdir before running
###############################################

# cmd = "rm -r #{opts[:outdir]}"
# log_cmd logger, cmd
# Process.run_it cmd

# run = nil
run = true

###############################################
# FOR TEST ONLY -- remove outdir before running
######################################################################


assert_file opts[:inaln]

inaln_info = File.parse_fname opts[:inaln]

outdir_tmp = File.join opts[:outdir], "tmp"

inaln_nogaps = File.join outdir_tmp,
                         "#{inaln_info[:base]}.nogaps.fa"

slayer_chimera_info = File.join opts[:outdir],
                                "#{inaln_info[:base]}" +
                                ".slayer.chimeras"
slayer_ids = File.join opts[:outdir],
                       "#{inaln_info[:base]}" +
                       ".slayer.accnos"

uchime_chimera_info = File.join opts[:outdir],
                                "#{inaln_info[:base]}" +
                                ".ref.uchime.chimeras"
uchime_ids = File.join opts[:outdir],
                       "#{inaln_info[:base]}" +
                       ".ref.uchime.accnos"

pintail_chimera_info = File.join opts[:outdir],
                                "#{inaln_info[:base]}" +
                                ".pintail.chimeras"
pintail_ids = File.join opts[:outdir],
                       "#{inaln_info[:base]}" +
                       ".pintail.accnos"

cluster_me = File.join outdir_tmp, "cluster_me.fa"
cluster_me_dist = File.join outdir_tmp, "cluster_me.phylip.dist"
cluster_me_list = File.join outdir_tmp, "cluster_me.phylip.an.list"
otu_file_base = File.join outdir_tmp, "cluster_me.phylip.an.0"
otu_file = ""

otu_calls =
  File.join opts[:outdir], "#{inaln_info[:base]}.otu_calls.txt"

chimeric_seqs =
  File.join opts[:outdir], "#{inaln_info[:base]}.dangerous_seqs.txt"


# containers

chimeric_ids = Set.new
db_otu_info  = {}
db_seq_ids = Set.new
db_seqs = {}
gap_posns = []
input_ids    = Set.new
input_seqs = {}
mask         = []
outgroup_names = Set.new
otu_info = []


# mothur params
mothur_params = "fasta=#{opts[:inaln]}, " +
                "reference=#{GOLD_ALN}, " +
                "outputdir=#{opts[:outdir]}, " +
                "processors=#{opts[:threads]}"

Time.time_it("Create needed directories", logger) do
  FileUtils.mkdir_p opts[:outdir]
  FileUtils.mkdir_p outdir_tmp
end

######################################################################
# process user input alignment
##############################

Time.time_it("Process input data", logger) do
  process_input_aln file: opts[:inaln],
                    seq_ids: input_ids,
                    seqs: input_seqs,
                    gap_posns: gap_posns
end

##############################
# process user input alignment
######################################################################

######################################################################
# read provided info
####################

Time.time_it("Read db OTU metadata", logger) do
  db_otu_info = read_otu_metadata opts[:db_otu_info]
  logger.debug { "DB OTU INFO: #{db_otu_info.inspect}" }
end

Time.time_it("Read mask info", logger) do
  mask = read_mask opts[:mask]
  logger.debug { "Num mask bases: #{mask.count}" }
end

Time.time_it("Update shared gap posns with db seqs", logger, run) do
  process_input_aln file: opts[:db_seqs],
                    seq_ids: db_seq_ids,
                    seqs: db_seqs,
                    gap_posns: gap_posns
end

Time.time_it("Read outgroups", logger) do
  File.open(OUTGROUPS).each_line do |line|
    outgroup_names << line.chomp
  end
end

####################
# read provided info
######################################################################


Time.time_it("Remove all gaps", logger) do
  cmd = "ruby #{REMOVE_ALL_GAPS} #{opts[:inaln]} > #{inaln_nogaps}"
  log_cmd logger, cmd
  Process.run_it! cmd
end

######################################################################
# slay the chimeras
###################

Time.time_it("Chimera Slayer", logger, run) do
  # in must be same length as reference
  cmd = "#{MOTHUR} " +
        "'#chimera.slayer(#{mothur_params})'"
  log_cmd logger, cmd
  Process.run_it! cmd
end

Time.time_it("Read slayer chimeras", logger, run) do
  File.open(slayer_ids).each_line do |line|
    id = line.chomp
    logger.debug { "Chimera Slayer flagged #{id}" }
    chimeric_ids << [id, "ChimeraSlayer"]
  end
end

Time.time_it("Uchime", logger, run) do
  cmd = "#{MOTHUR} " +
        "'#chimera.uchime(#{mothur_params})'"
  log_cmd logger, cmd
  Process.run_it! cmd
end

Time.time_it("Read uchime chimeras", logger, run) do
  File.open(uchime_ids).each_line do |line|
    id = line.chomp
    logger.debug { "Uchime flagged #{id}" }
    chimeric_ids << [id, "uchime"]
  end
end

Time.time_it("Pintail", logger, run) do
  cmd = "#{MOTHUR} " +
        "'#chimera.pintail(fasta=#{opts[:inaln]}, " +
        "template=#{GOLD_ALN}, " +
        "conservation=#{SILVA_FREQ}, " +
        "quantile=#{SILVA_QUAN}, " +
        "outputdir=#{opts[:outdir]}, " +
        "processors=#{opts[:threads]})'"
  log_cmd logger, cmd
  Process.run_it! cmd
end

Time.time_it("Read Pintail chimeras", logger, run) do
  File.open(pintail_ids).each_line do |line|
    id = line.chomp
    logger.debug { "Pintail flagged #{id}" }
    chimeric_ids << [id, "Pintail"]
  end
end

Time.time_it("Write chimeric seqs", logger) do
  File.open(chimeric_seqs, "w") do |f|
    chimeric_ids.each do |id, software|
      f.puts [id, software].join "\t"
      logger.debug { "#{id} was flagged as chimeric by #{software}" }
    end
  end

  logger.info { "Chimeric seqs written to #{chimeric_seqs}" }
end

###################
# slay the chimeras
######################################################################

######################################################################
# cluster
#########

Time.time_it("Write combined fasta", logger, run) do
  File.open(cluster_me, "w") do |f|
    input_seqs.each { |head, seq| f.printf ">%s\n%s\n", head, seq }
    db_seqs.each { |head, seq| f.printf ">%s\n%s\n", head, seq }
  end
end

Time.time_it("Distance", logger, run) do
  cmd = "#{MOTHUR} " +
        "'#dist.seqs(fasta=#{cluster_me}, " +
        "outputdir=#{outdir_tmp}, " +
        "output=lt, " +
        "processors=#{opts[:threads]})'"

  log_cmd logger, cmd
  Process.run_it! cmd
end

Time.time_it("Cluster", logger, run) do
  cmd = "#{MOTHUR} " +
        "'#cluster(phylip=#{cluster_me_dist})'"

  log_cmd logger, cmd
  Process.run_it! cmd
end

Time.time_it("Get OTU list", logger, run) do
  cmd = "#{MOTHUR} '#get.otulist(list=#{cluster_me_list})'"
  log_cmd logger, cmd
  Process.run_it! cmd
end


#########
# cluster
######################################################################

######################################################################
# assigned detailed OTU info
############################

Time.time_it("Find OTU file", logger) do
  %w[03 02 01].each do |pid|
    otu_file = "#{otu_file_base}.#{pid}.otu"
    break if File.exists? otu_file
    logger.debug { "OTU file #{otu_file} not found" }
  end

  assert_file otu_file
  logger.debug { "For OTUs, using #{otu_file}" }
end

Time.time_it("Read OTUs", logger) do
  # TODO generate good names for new OTUs
  File.open(otu_calls, "w") do |f|
    File.open(otu_file).each_line do |line|
      otu, id_str = line.chomp.split "\t"
      ids = id_str.split ","

      refute ids.count.zero?
      logger.debug { "MOTHUR OTU #{otu} had #{ids.count} sequence(s)" }

      this_otu_usr_seqs = Set.new
      otu_info = ids.map do |id|
        if db_otu_info.has_key? id
          db_otu_info[id][:otu]
        else
          assert_includes input_ids, id
          this_otu_usr_seqs << id
          "USR"
        end
      end

      logger.debug { "OTU info: #{otu_info.inspect}" }

      # TODO this is printing out non user seqs
      if ids.all? { |id| id == "USR" }
        ids.each do |id|
          f.puts [id, "NEW", "NA"].join "\t"
        end
      else otu_info.include? "USR"
        if ids.count > 1
          otu_counts = otu_info.
                       reject { |otu| otu == "USR" }.
                       group_by(&:itself).
                       map { |otu, arr| [otu, arr.count] }.
                       sort_by { |otu, count| count }.
                       reverse

          logger.debug { "OTU counts: #{otu_counts.inspect}" }

          non_usr_count = otu_counts.map(&:last).reduce(:+).to_f
          logger.debug { "MOTHUR OTU #{otu} non user sequence count: " +
                         "#{non_usr_count}" }

          otu_percs =
            otu_counts.map { |otu, count| [otu, count / non_usr_count] }

          logger.debug { "OTU percs: #{otu_percs.inspect}" }

          this_otu_usr_seqs.each do |id|
            f.puts [id, otu_percs.first.first, otu_percs.inspect].join "\t"
          end
        else
          f.puts [ids.first, "NEW", "NA"].join "\t"
        end
      end
    end
  end

  logger.info { "OTU calls written to #{otu_calls}" }
end

############################
# assigned detailed OTU info
######################################################################

######################################################################
# clean up
##########

Time.time_it("Clean up", logger) do
  FileUtils.rm Dir.glob File.join File.dirname(__FILE__), "mothur.*.logfile"
  FileUtils.rm Dir.glob File.join File.dirname(__FILE__), "formatdb.log"
  FileUtils.rm Dir.glob File.join TEST_DIR, "*.tmp.uchime_formatted"
  FileUtils.rm Dir.glob File.join opts[:outdir], "mothur.*.logfile"
end

##########
# clean up
######################################################################
