# frozen_string_literal: true
class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior
  include BlacklightAdvancedSearch::AdvancedSearchBuilder
  self.default_processor_chain += [:add_advanced_search_to_solr, :override_sort_when_q_is_empty, :lowercase_expert_boolean_operators,
      :add_left_anchored_title]
  include BlacklightRangeLimit::RangeLimitBuilder
  include BlacklightSolrplugins::FacetFieldsQueryFilter

  # override #with to massage params before this SearchBuilder
  # stores and works with them
  def with(blacklight_params = {})
    params_copy = blacklight_params.dup
    if params_copy[:q].present?
      # #add_query_to_solr assumes the presence of search_field, which we don't set
      # on bento page, so we set it here if absent. we MUST do this, otherwise
      # the code that adds the field's solr_local_parameters, which we use to
      # set qf/pf params, won't run.
      search_field = params_copy[:search_field] || default_search_field.field
      params_copy[:search_field] = search_field
      if search_field != 'keyword_expert' && !is_advanced_search?
        params_copy[:q] = params_copy[:q].gsub(/[\?]/, '')
      end
      # colons surrounded by whitespace cause Solr to return 0 results
      params_copy[:q] = params_copy[:q].gsub(/\s+:\s+/, ' ')
      if search_field == 'keyword_expert'
        params_copy[:q] = params_copy[:q].gsub(/(^| )bib_id:([0-9]+)/, '\1alma_mms_id:99\23503681')
      end
    end
    super(params_copy)
  end

  def add_left_anchored_title(solr_parameters)
    bq = blacklight_params[:q]
    return if !bq.present?
    solr_parameters[:qq] = bq
    augmented_solr_q = '{!maxscore}_query_:"{!edismax sow=false q.op=AND qf=\'title_1_tl^0\' pf=\'title_1_tl^12\' v=$qq}" OR _query_:"'\
        + solr_parameters[:q] + '"'
    solr_parameters[:q] = augmented_solr_q
  end

  # no q param (with or without facets) causes the default 'score' sort
  # to return results in a different random order each time b/c there's
  # no scoring to apply. if there's no q and user hasn't explicitly chosen
  # a sort, we sort by id to provide stable deterministic ordering.
  def override_sort_when_q_is_empty(solr_parameters)
    blacklight_sort = blacklight_params[:sort]
    return if blacklight_sort.present? && blacklight_sort != 'score desc'
    access_f = blacklight_params.dig(:f, :access_f)
    if !blacklight_params[:q].present?
      sort = 'elvl_rank_isort asc,last_update_isort desc'
      if access_f.nil? || access_f.empty?
	# nothing
      elsif access_f.include? 'At the library'
        if access_f.size == 1
          # privilege physical holdings
          sort = "min(def(hld_count_isort,0),1) desc,#{sort}"
        end
      else
	# privilege online holdings
        sort = "min(def(prt_count_isort,0),1) desc,#{sort}"
      end
    else
      sort = solr_parameters[:sort]
      sort = 'score desc' if !sort.present?
      if access_f == nil || access_f.empty?
        sort = "#{sort},min(max(def(hld_count_isort,0),def(prt_count_isort,0)),10) desc"
      elsif access_f.size == 1 && access_f.first == 'At the library'
        sort = "#{sort},min(def(hld_count_isort,0),10) desc,min(def(prt_count_isort,0),10) desc"
      else
        sort = "#{sort},min(def(prt_count_isort,0),10) desc,min(def(hld_count_isort,0),10) desc"
      end
    end
    solr_parameters[:sort] = sort
  end

  def lowercase_expert_boolean_operators(solr_parameters)
    search_field = blacklight_params[:search_field]
    if search_field == 'keyword_expert'
      solr_parameters[:lowercaseOperators] = true
    end
  end

end
