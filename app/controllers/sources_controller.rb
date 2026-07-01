# frozen_string_literal: true

# CRUD for streaming provider definitions. New/edit are rendered as modals on the
# watch page, so this controller only handles index + the write actions and redirects
# back to wherever the form was submitted from.
class SourcesController < ApplicationController
  before_action :require_admin
  before_action :set_source, only: %i[update destroy]

  def index
    @sources = Source.order(:position, :name)
  end

  def create
    @source = Source.new(source_params)
    if @source.save
      flash[:notice] = "Source '#{@source.name}' created"
    else
      flash[:alert] = @source.errors.full_messages.to_sentence
    end
    redirect_back(fallback_location: sources_path)
  end

  def update
    if @source.update(source_params)
      flash[:notice] = "Source '#{@source.name}' updated"
    else
      flash[:alert] = @source.errors.full_messages.to_sentence
    end
    redirect_back(fallback_location: sources_path)
  end

  def destroy
    name = @source.name
    @source.destroy # has_many ... dependent: :nullify -> referencing entries/lists fall back
    flash[:notice] = "Source '#{name}' deleted; affected entries fall back to their list default"
    redirect_back(fallback_location: sources_path)
  end

  private

  def require_admin
    return if current_user&.admin?

    redirect_back(fallback_location: root_path, alert: "Only admins can manage sources")
  end

  def set_source
    @source = Source.find(params[:id])
  end

  def source_params
    permitted = params.require(:source).permit(
      :name, :slug, :kind, :autoplay_param, :active, :position,
      templates: %i[movie series episode anime default]
    )
    # Drop blank template patterns so we never store empty strings in the jsonb.
    if permitted[:templates]
      permitted[:templates] = permitted[:templates].to_h.reject { |_, v| v.blank? }
    end
    permitted
  end
end
