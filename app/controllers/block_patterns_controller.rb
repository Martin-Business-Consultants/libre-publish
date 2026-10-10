# frozen_string_literal: true

# Content › Patterns: sets of blocks to use again (BlockPattern). Editing one
# is the block editor pages use; inserting one is the block picker's
# Patterns section (content_blocks#new). Patterns are part of writing pages,
# so they take the pages capabilities.
class BlockPatternsController < ApplicationController
  include ContentEditing

  requires_capability "pages:read",   only: :index
  requires_capability "pages:write",  only: [:new, :create, :edit, :update]
  requires_capability "pages:delete", only: :destroy

  before_action :set_pattern, only: [:edit, :update, :destroy]

  def index
    @patterns = BlockPattern.ordered
  end

  def new
    @pattern = BlockPattern.new
  end

  def create
    @pattern = BlockPattern.new(pattern_attributes(BlockPattern.new))
    if @pattern.save
      redirect_to edit_block_pattern_path(@pattern), notice: "Pattern saved"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @pattern.update(pattern_attributes(@pattern))
      redirect_to edit_block_pattern_path(@pattern), notice: "Pattern saved"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @pattern.destroy!
    redirect_to block_patterns_path, notice: "Pattern deleted. A page that placed it synced shows nothing in its place."
  end

  private

  def set_pattern
    @pattern = BlockPattern.find_by!(slug: params[:slug])
  end

  def pattern_attributes(pattern)
    attributes = params.require(:block_pattern).permit(:name, :slug, :description, :synced).to_h
    attributes["blocks"] = decoded_content_blocks(:block_pattern, pattern.blocks)
    attributes
  end
end
