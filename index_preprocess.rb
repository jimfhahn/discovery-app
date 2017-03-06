#!/usr/bin/env ruby
#
# For parallelism, you can run this using xargs as follows:
#
# time ls ~/marc/alma_prod_sandbox/2017_03_03_oai_million_set_large_batch/*.xml | sort | xargs --verbose -I{} -P 4 ./index_preprocess.rb -o {}

require 'optparse'
require 'pathname'

def parse_options
  options = {
    chunk_size: nil,
    oai: false,
    resume: false,
    format: false,
  }
  opt_parser = OptionParser.new do |opts|
    opts.banner = 'Usage: index_preprocess.rb [options] FILE'

    opts.separator ""
    opts.separator "This utility preprocesses Alma MARC XML exports so they're ready"
    opts.separator "for indexing. This includes splitting up files, fixing namespace"
    opts.separator "and data problems in the MARC XML, and formatting for readability."
    opts.separator ""

    opts.on('-c', '--chunk-size SIZE', 'Number of records per chunk file') do |v|
      options[:chunk_size] = v.to_i
    end
    opts.on('-o', '--oai', 'Convert from OAI') do |v|
      options[:oai] = true
    end
    opts.on('-r', '--resume', 'Resume mode (skip already processed files)') do |v|
      options[:resume] = true
    end
    opts.on('-f', '--format', 'Format (prettify) XML using xmllint (defaults to false)') do |v|
      options[:format] = true
    end
    opts.on_tail('-h', '--help', 'Show this message') do
      puts opts
      exit
    end
  end
  opt_parser.parse!
  [ options, opt_parser ]
end

def run(command)
  result = system(command)
  if !result
    puts "error occurred running this command: #{command}"
    puts 'stopping.'
    exit 1
  end
end

def check_file_exists(path)
  if !File.exist?(path)
    puts "Error: expected file #{path} to exist. Stopping."
    exit 1
  end
end

def rm_if_not_original(filename, original_filename)
  if filename != original_filename
    File.delete(filename)
  end
end

def final_filename(filename)
  "part#{filename.scan(/\d+/)[0]}.xml"
end

def main
  options, opt_parser = parse_options

  if ARGV.length == 0
    puts opt_parser.help
    exit
  end

  script_dir = File.expand_path(File.dirname(__FILE__))
  xsl_dir = "#{script_dir}/xsl"

  # as the Hash moves through this pipeline, 'file' is always the
  # result of the most recent transformation.

  ARGV.lazy.map { |path|
    {
      original_file: File.basename(File.expand_path(path)),
      file: File.basename(File.expand_path(path)),
      dir: File.dirname(File.expand_path(path))
    }
  }.select { |struct|
    !options[:resume] || !File.exist?(final_filename(struct[:file]))
  }.map { |struct|
    if options[:oai]
      Dir.chdir(struct[:dir])
      marc_file = struct[:file].gsub('.xml', '_marc.xml')
      run(%Q!JAVA_OPTS="-Xms3g -Xmx3g" saxon -s:#{struct[:file]} -xsl:#{xsl_dir}/oai2marc.xsl -o:#{marc_file}!)
      struct[:file] = marc_file
    end
    struct
  }.flat_map { |struct|
    if !options[:chunk_size].nil?
      Dir.chdir(struct[:dir])
      run("#{script_dir}/split.sh #{struct[:file]} #{options[:chunk_size]}")
      rm_if_not_original(struct[:file], struct[:original_file])
      Dir.glob("#{struct[:file]}_*.xml").map do |path|
        { file: path, original_file: struct[:original_file], dir: struct[:dir] }
      end
    else
      [ struct ]
    end
  }.map { |struct|
    fixed_file = Pathname.new(struct[:file]).basename('.xml').to_s + '_fixed.xml'
    Dir.chdir(struct[:dir])
    run(%Q!JAVA_OPTS="-Xms3g -Xmx3g" saxon -s:#{struct[:file]} -xsl:#{xsl_dir}/fix_alma_prod_marc_records.xsl -o:#{fixed_file}!)
    check_file_exists(fixed_file)
    rm_if_not_original(struct[:file], struct[:original_file])
    struct[:file] = fixed_file
    struct
  }.map { |struct|
    file = struct[:file]
    part_file = final_filename(struct[:file])
    if options[:format]
      run("xmllint --format #{fixed_file} > #{part_file}")
      check_file_exists(part_file)
      rm_if_not_original(file, struct[:original_file])
    else
      File.rename(file, part_file)
      check_file_exists(part_file)
    end
    struct[:file] = part_file
    struct
  }.each { |struct|
    puts "done with #{struct[:file]}"
  }

end

main

exit 0
