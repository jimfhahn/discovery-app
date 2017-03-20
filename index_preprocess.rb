#!/usr/bin/env ruby
#
# Preprocessing of Alma export files in preparation for indexing into Solr
#
# time ./index_preprocess.rb -x /home/jeffchiu/blacklight_dev/xsl -p 4 -i "~/marc/alma_prod_sandbox/20170315_full/raw/fulltest*.xml" fix_namespace create_bound_withs
# time bundle exec rake pennlib:marc:create_boundwiths_index BOUND_WITHS_DB_FILENAME=bound_withs.sqlite3 BOUND_WITHS_GLOB="/home/jeffchiu/marc/alma_prod_sandbox/20170315_full/raw/boundwiths_*.xml"
# time ./index_preprocess.rb -x /home/jeffchiu/blacklight_dev/xsl -p 4 -i "~/marc/alma_prod_sandbox/20170315_full/raw/fulltest*.xml" fix_marc merge_bound_withs format rename_to_final_filename

load 'file_pipeline.rb'

pipeline = FilePipeline.define do

  script_dir = File.expand_path(File.dirname(__FILE__))

  option_parser do |parser, options|
    parser.on('-x', '--xsl-dir XSL_DIR', 'Directory where .xsl files are stored') do |v|
      options[:xsl_dir] = v
    end
  end

  step :fix_namespace
  run do |stage|
    # this modifies the file in-place, so we don't delete the input file
    run_command(%(sed -i 's/<collection>/<collection xmlns=\\"http:\\/\\/www.loc.gov\\/MARC21\\/slim\\">/' #{stage.filename}))
  end

  step :create_bound_withs
  run do |stage|
    # bound with files are used by later stage of preprocessing; we don't delete the input file
    boundwiths_file = "boundwiths_#{stage.filename.scan(/\d+/)[-1]}.xml"
    run_command(%(JAVA_OPTS="-Xms3g -Xmx3g" saxon -s:#{stage.filename} -xsl:#{options[:xsl_dir]}/boundwith_holdings.xsl -o:#{boundwiths_file}))
  end

  step :merge_bound_withs
  delete_input_file true
  run do |stage|
    chdir(script_dir)
    merged_file = Pathname.new(stage.dir).join("merged_#{stage.filename.scan(/\d+/)[-1]}.xml").to_s
    run_command(%(bundle exec rake pennlib:marc:merge_boundwiths BOUND_WITHS_DB_FILENAME=bound_withs.sqlite3 BOUND_WITHS_INPUT_FILE=#{stage.complete_path} BOUND_WITHS_OUTPUT_FILE=#{merged_file}))
    { output_file: merged_file }
  end

  step :convert_oai_to_marc
  delete_input_file true
  run do |stage|
    marc_file = stage.filename.gsub('.xml', '_marc.xml')
    run_command(%(JAVA_OPTS="-Xms3g -Xmx3g" saxon -s:#{stage.filename} -xsl:#{options[:xsl_dir]}/oai2marc.xsl -o:#{marc_file}))
    { output_file: marc_file }
  end

  step :fix_marc
  delete_input_file true
  run do |stage|
    fixed_file = Pathname.new(stage.filename).basename('.xml').to_s + '_fixed.xml'
    run_command(%(JAVA_OPTS="-Xms3g -Xmx3g" saxon -s:#{stage.filename} -xsl:#{options[:xsl_dir]}/fix_alma_prod_marc_records.xsl -o:#{fixed_file} bound_with_dir=#{stage.dir}))
    { output_file: fixed_file }
  end

  step :format
  delete_input_file true
  run do |stage|
    formatted_file = Pathname.new(stage.filename).basename('.xml').to_s + '_formatted.xml'
    run_command("xmllint --format #{stage.filename} > #{formatted_file}")
    { output_file: formatted_file }
  end

  step :rename_to_final_filename
  run do |stage|
    part_file = "part#{stage.filename.scan(/\d+/)[-1]}.xml"
    File.rename(stage.filename, part_file)
  end
end

pipeline.execute
