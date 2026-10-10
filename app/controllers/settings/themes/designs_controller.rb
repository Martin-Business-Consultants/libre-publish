# frozen_string_literal: true

# Settings › Themes › Customize: a theme's design settings (Website::Design),
# its colors, fonts and choices. Saving changes the website at once (the
# settings are part of its cache version); Reset goes back to the theme's
# defaults.
class Settings::Themes::DesignsController < Settings::BaseController
  requires_capability "settings:read", only: :edit
  requires_capability "settings:write", only: [:update, :destroy]

  before_action :set_theme

  def edit
    @values = Website::Design.values(@theme)
  end

  def update
    Website::Design.update(@theme, params.fetch(:design, {}).permit(@theme.settings.map(&:name)).to_h)
    redirect_to edit_settings_theme_design_path(@theme.key), notice: "#{@theme.name}’s design is saved."
  end

  def destroy
    Website::Design.reset(@theme)
    redirect_to edit_settings_theme_design_path(@theme.key), notice: "#{@theme.name} is back to its own design."
  end

  private

  def set_theme
    @theme = Website.themes[params[:theme_key].to_s] or raise ActiveRecord::RecordNotFound
  end
end
