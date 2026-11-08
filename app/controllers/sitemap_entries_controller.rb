# frozen_string_literal: true

# One row of the admin Sitemap page, edited in place: its status and its
# sitemap settings (Sitemapped). Rich SEO and content editing go through the
# ordinary page and entry forms.
class SitemapEntriesController < ApplicationController
  requires_capability "pages:write", only: :update

  def update
    record = Sitemap.record_for(params[:source], params[:id])
    return redirect_to(sitemap_path, alert: "Record not found") unless record

    settings = params.require(:entry).permit(:status, *Sitemapped::SETTINGS)
    record.status = settings[:status] if Page::STATUSES.include?(settings[:status])
    record.change_sitemap_settings(settings.except(:status))

    # One gate (PublishGated): a status change, or any change to a live row.
    if record.publishing_write? && !granted?(Sitemap.publish_capability(params[:source]))
      return redirect_to(sitemap_path(show: params[:show].presence), alert: "Changing a live row, or its status, needs permission to publish.")
    end

    if record.save
      record.track_sitemap_update(source: params[:source])
      redirect_to sitemap_path(show: params[:show].presence), notice: "Sitemap entry updated"
    else
      redirect_to sitemap_path(show: params[:show].presence), alert: record.errors.full_messages.to_sentence
    end
  end
end
