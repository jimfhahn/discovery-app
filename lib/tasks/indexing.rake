
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

        SolrMarc.indexer =
          case ENV['MARC_SOURCE']
            when 'CRL'
              CrlIndexer.new
            when 'HATHI'
              HathiIndexer.new
            else
              FranklinIndexer.new
          end

        Rake::Task['solr:marc:index:work'].execute
        puts "Finished indexing #{file} at #{DateTime.now}"
      end
    end

    desc "Index MARC data from stdin"
    task :index_from_stdin  => :environment do |t, args|
      SolrMarc.indexer =
        case ENV['MARC_SOURCE']
          when 'CRL'
            CrlIndexer.new
          when 'HATHI'
            HathiIndexer.new
          else
            FranklinIndexer.new
        end

      SolrMarc.indexer.process(STDIN)
    end

    # for debugging
    desc "Index MARC records and output to file (for debugging)"
    task :index_to_file => :environment do |t, args|

      class MyMarcIndexer < HathiIndexer
        def initialize
          super
          settings do
            store "writer_class_name", "Traject::JsonWriter"
            store 'output_file', "traject_output.json"
          end
        end
      end

      io = Zlib::GzipReader.new(File.open('/home/jeffchiu/hathi-oai-marc/processed/part_929.xml.gz'), :external_encoding => 'UTF-8')
      MyMarcIndexer.new.process(io)
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

    desc "Dump OCLC IDs"
    task :dump_oclc_ids => :environment do |t, args|
      code_mappings ||= PennLib::CodeMappings.new(Rails.root.join('config').join('translation_maps'))
      pennlibmarc ||= PennLib::Marc.new(code_mappings)

      Dir.glob('/home/jeffchiu/hathi-oai-marc/processed/part*.xml.gz').each do |file|
        io = Zlib::GzipReader.new(File.open(file), :external_encoding => 'UTF-8')
        reader = MARC::XMLReader.new(io)
        reader.each do |record|
          pennlibmarc.get_oclc_id_values(record).each do |oclc_id|
            puts oclc_id
          end
        end
        io.close()
      end
    end

    desc "Create boundwiths index"
    task :create_boundwiths_index => :environment do |t, args|
      PennLib::BoundWithIndex.create(
          ENV['BOUND_WITHS_DB_FILENAME'],
          ENV['BOUND_WITHS_XML_DIR']
      )
    end

    desc "Merge boundwiths into records"
    task :merge_boundwiths => :environment do |t, args|
      input_filename = ENV['BOUND_WITHS_INPUT_FILE']
      output_filename = ENV['BOUND_WITHS_OUTPUT_FILE']
      input = (input_filename && File.exist?(input_filename)) ? PennLib::Util.openfile(input_filename) : STDIN
      output = (output_filename && File.exist?(output_filename)) ? PennLib::Util.openfile(output_filename) : STDOUT
      PennLib::BoundWithIndex.merge(ENV['BOUND_WITHS_DB_FILENAME'], input, output)
    end

  end

  namespace :oai do

    desc 'Parse IDs from OAI file and delete them from Solr index'
    task :delete_ids => :environment do |t, args|
      input_filename = ENV['OAI_FILE']
      input = (input_filename && File.exist?(input_filename)) ? PennLib::Util.openfile(input_filename) : STDIN
      PennLib::OAI.delete_ids_in_file(input)
    end

  end

  namespace :db do
    desc 'Delete old data from database'
    task :delete_old_data => :environment do |t, args|

      days_old_for_searches = 1
      Rake::Task['blacklight:delete_old_searches'].invoke(days_old_for_searches)

      # we don't use the devise_guests:delete_old_guest_users task
      # because it deletes records one at a time (!)

      days_old_for_users = 4
      User.where("guest = ? and updated_at < ?", true, Time.now - days_old_for_users.to_i.days).destroy_all
    end
  end

end
