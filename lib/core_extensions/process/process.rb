# Copyright 2016 - 2018 Ryan Moore
# Contact: moorer@udel.edu
#
# This file is part of ZetaHunter.
#
# ZetaHunter is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ZetaHunter is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ZetaHunter.  If not, see <http://www.gnu.org/licenses/>.

require "systemu"
require_relative "../../abort_if/abort_if"

module CoreExtensions
  module Process
    def run_it *a, &b
      exit_status, stdout, stderr = systemu *a, &b

      puts stdout unless stdout.empty?
      $stderr.puts stderr unless stderr.empty?

      exit_status.exitstatus
    end

    def run_it! *a, &b
      exit_status = self.run_it *a, &b

      AbortIf::Abi.abort_unless exit_status.zero?,
                       "ERROR: non-zero exit status (#{exit_status})"

      exit_status
    end
  end
end
