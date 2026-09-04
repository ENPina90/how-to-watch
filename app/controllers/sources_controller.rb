# frozen_string_literal: true

# CRUD for streaming provider definitions. New/edit are rendered as modals on the
# watch page, so this controller only handles index + the write actions and redirects
# back to wherever the form was submitted from.
class SourcesController < ApplicationController
  before_action :require_admin
  before_action :set_source, only: %i[update destroy renew deactivate test]

  # Ordered by position, because that order is now something an admin sets by hand and it
  # is also what the app falls back through. Expiry is shown by colour rather than by
  # sorting, so a warning cannot silently rearrange a list somebody arranged.
  def index
    @sources = Source.order(:position, :name)
  end

  # Persists a drag on the index. The whole order arrives at once -- see Source.reorder!.
  def reorder
    Source.reorder!(params.require(:ids))

    head :no_content
  end

  # Buys another year (see Source#renew!). Its own action rather than a field on the edit
  # form because it is the answer to a warning, and wants to be one click from it.
  def renew
    @source.renew!

    redirect_back fallback_location: sources_path,
                  notice: "#{@source.name} is now good until #{@source.valid_until.to_fs(:long)}."
  end

  # Switching a provider off rather than deleting it: nothing that references it is
  # disturbed, entries fall back the way they already do when a provider is inactive, and
  # it can be switched back on. Deleting stays available for a provider that is really gone.
  def deactivate
    @source.update!(active: false)

    redirect_back fallback_location: sources_path,
                  notice: "#{@source.name} is off. Channels on it fall back to the next active provider."
  end

  # Plays one known title through this provider and nothing else. Opened in a new tab from
  # the index, so the answer to "is this domain still alive" is a glance rather than a hunt
  # for an entry that happens to use it.
  def test
    @probe_url = @source.probe_url
    @probe_label = @source.probe_label
    @hide_sidebar = true

    render layout: 'application'
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

  # Same terms as /admin and /sidekiq: the check is on `true_user`, and it refuses while
  # impersonating. Managing providers is the admin's own job, not part of what they are
  # looking at when they view the site as somebody else -- and the navbar link only appears
  # under those conditions, so the page and the link agree.
  def require_admin
    return if true_user&.admin? && !impersonating?

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
