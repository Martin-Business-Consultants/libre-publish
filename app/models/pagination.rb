# frozen_string_literal: true

# One page of an index table, numbered as WordPress's are: PER_PAGE rows a
# page, and below the table « Previous, the page numbers (1 … 4 5 6 … 13) and
# Next » (layouts/shared/_pagination). Pages a relation (by offset and limit,
# counted once) or an array (Trash, the sitemap). A page past the last shows
# the last, so a list that shrank under someone's feet isn't empty.
#
#   @pagination = Pagination.new(Page.order(:path), page: params[:page])
#   @pagination.records   # this page's rows
class Pagination
  PER_PAGE = 25
  # Page numbers either side of the current one before a gap.
  AROUND = 2

  attr_reader :per

  def initialize(collection, page: 1, per: PER_PAGE)
    @collection = collection
    @per = per
    # Only a number: on Pages, params[:page] is also the new-page form.
    @requested = (page.is_a?(String) || page.is_a?(Integer)) ? page.to_i : 1
  end

  def total_count
    @total_count ||= @collection.respond_to?(:count) && !@collection.is_a?(Array) ? @collection.count(:all) : @collection.size
  end

  def page_count = [(total_count / per.to_f).ceil, 1].max

  def number = @requested.clamp(1, page_count)

  def records
    @records ||= if @collection.is_a?(Array)
      @collection.slice(offset, per) || []
    else
      @collection.offset(offset).limit(per)
    end
  end

  def first? = number == 1
  def last? = number == page_count
  def previous_number = (number - 1 unless first?)
  def next_number = (number + 1 unless last?)
  def many? = page_count > 1

  # The rows this page shows, counted from one ("26–50 of 312").
  def first_row = total_count.zero? ? 0 : offset + 1
  def last_row = [offset + per, total_count].min

  # The numbers to link, with nil for each gap: the first and last pages
  # always, and AROUND either side of this one.
  #
  #   page 6 of 13 → [1, nil, 4, 5, 6, 7, 8, nil, 13]
  def window
    shown = ([1, page_count] + ((number - AROUND)..(number + AROUND)).to_a).select { it.between?(1, page_count) }.uniq.sort
    shown.each_with_object([]) do |n, numbers|
      if numbers.last && n - numbers.last > 1
        numbers << (n - numbers.last == 2 ? n - 1 : nil)
      end
      numbers << n
    end
  end

  private

  def offset = (number - 1) * per
end
