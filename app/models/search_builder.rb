# frozen_string_literal: true
class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior
  include BlacklightAdvancedSearch::AdvancedSearchBuilder
  self.default_processor_chain += [:add_advanced_parse_q_to_solr, :add_advanced_search_to_solr, :override_sort_when_q_is_empty ]
  include BlacklightRangeLimit::RangeLimitBuilder
  include BlacklightSolrplugins::FacetFieldsQueryFilter

  # no q param (with or without facets) causes the default 'score' sort
  # to return results in a different random order each time b/c there's
  # no scoring to apply. if there's no q and user hasn't explicitly chosen
  # a sort, we sort by id to provide stable deterministic ordering.
  def override_sort_when_q_is_empty(solr_parameters)
    if !blacklight_params[:q].present? && !blacklight_params[:sort].present?
      solr_parameters[:sort] = 'id asc'
    end
  end

end
