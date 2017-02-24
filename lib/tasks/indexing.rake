
require 'date'

namespace :pennlib do
  namespace :marc do

    # This is a wrapper around the "solr:marc:index" task
    # to get around the single file limitation (JRuby has a very long
    # start-up time for each time you spawn a new indexing process
    # per file).
    #
    # With this task, the MARC_FILE env variable can be a glob,
    # such as "/data/*.xml"
    desc "Index multiple MARC files"
    task :index  => :environment do |t, args|

      marc_file_original = ENV['MARC_FILE']

      files = Dir.glob(marc_file_original).sort!
      files.each do |file|
        puts "Started indexing #{file} at #{DateTime.now}"
        ENV['MARC_FILE'] = file
        Rake::Task['solr:marc:index:work'].execute
        puts "Finished indexing #{file} at #{DateTime.now}"
      end

    end

    # for debugging
    desc "Index MARC records and output to file (for debugging)"
    task :index_to_file => :environment do |t, args|

      class MyMarcIndexer < MarcIndexer
        def initialize
          super
          settings do
            store "writer_class_name", "Traject::JsonWriter"
            store 'output_file', "traject_output.json"
          end
        end
      end

      MyMarcIndexer.new.process('/home/jeffchiu/marc/alma_prod_sandbox/smallbatch/fixed/fixed.xml')
    end

    # for debugging: this seems braindead but is actually useful: the
    # marc reader will raise an exception if it can't marshal the XML
    # into Record objects
    desc "Just read MARC records and do nothing"
    task :read_marc => :environment do |t, args|
      reader = MARC::XMLReader.new('/home/jeffchiu/marc/alma_prod_sandbox/20170223/split/chunk_3.xml')
      last_id = nil
      begin
        reader.each do |record|
          record.fields('001').each { |field| last_id = field.value }
        end
      rescue Exception => e
        puts "last record successfully read=#{last_id}"
        raise e
      end
    end

  end
end
