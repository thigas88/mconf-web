module Abilities

  class AnonymousAbility < BaseAbility

    def register_abilities(user=nil)
      abilities_for_bigbluebutton_rails(user)

      # Note: For the private profile only, the public profile is always visible.
      #   Check for public profile with `can?(:show, user)` instead of `can?(:show, user.profile)`.
      can :read, Profile do |profile|
        resource_enabled?(profile.user) &&
          case profile.visibility
          when Profile::VISIBILITY.index(:everybody)
            true
          else
            false
          end
      end

      can [:read, :current], User, disabled: false
      can [:read, :webconference, :recordings], Space, public: true, disabled: false
      can :select, Space, disabled: false
      can :read, Post, space: { public: true, disabled: false }
      can :show, News, space: { public: true, disabled: false }
      can :read, Attachment, space: { public: true, repository: true, disabled: false }

      # Events from MwebEvents
      if Mconf::Modules.mod_loaded?('events')
        can [:read, :select], MwebEvents::Event do |e|
          if e.owner_type == "Space"
            resource_enabled?(e.owner)
          else
            true
          end
        end
        can :register, MwebEvents::Event do |e|
          if e.owner_type == "Space"
            resource_enabled?(e.owner) && e.public
          else
            e.public
          end
        end
        # TODO: really needed?
        can :create, MwebEvents::Participant do |p|
          if p.event.present? && p.event.owner_type == "Space"
            resource_enabled?(e.owner)
          else
            true
          end
        end
      end
    end

    private

    def abilities_for_bigbluebutton_rails(user)
      # Recordings of public spaces are available to everyone
      can [:space_show, :play], BigbluebuttonRecording do |recording|
        recording.room.try(:public?)
      end

      # some actions in rooms should be accessible to anyone
      can [:invite, :invite_userid, :join, :join_mobile, :running], BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          (room.owner_type == "User" || room.owner_type == "Space")
      end
    end

  end
end
