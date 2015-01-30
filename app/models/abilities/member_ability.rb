module Abilities

  class MemberAbility < BaseAbility
    def register_abilities(user)
      abilities_for_bigbluebutton_rails(user)

      # Users
      # Disabled users are only visible to superusers
      can [:read, :fellows, :current, :select], User, disabled: false
      can [:edit, :update, :destroy], User, id: user.id, disabled: false

      # User profiles
      # Visible according to options selected by the user, editable by their owners
      # Note: For the private profile only, the public profile is always visible.
      #   Check for public profile with `can?(:show, user)` instead of `can?(:show, user.profile)`.
      can :read, Profile do |profile|
        resource_enabled?(profile.user) &&
          case profile.visibility
          when Profile::VISIBILITY.index(:everybody)
            true
          when Profile::VISIBILITY.index(:members)
            true
          when Profile::VISIBILITY.index(:public_fellows)
            profile.user.public_fellows.include?(user)
          when Profile::VISIBILITY.index(:private_fellows)
            profile.user.private_fellows.include?(user)
          when Profile::VISIBILITY.index(:nobody)
            false
          end
      end
      can [:read, :edit, :update, :update_logo], Profile, user_id: user.id, user: { disabled: false }

      # Private messages
      can :create, PrivateMessage
      can :read, PrivateMessage do |message|
        [message.sender_id, message.receiver_id].include?(user.id)
      end
      can :destroy, PrivateMessage do |message|
        [message.sender_id, message.receiver_id].include?(user.id)
      end

      # Spaces
      can [:create, :select], Space, disabled: false
      can [:read, :webconference, :recordings], Space, public: true, disabled: false
      can [:read, :webconference, :recordings, :leave], Space do |space|
        resource_enabled?(space) &&
          space.users.include?(user)
      end
      # Only the admin can disable or update information on a space
      # Only global admins can destroy spaces
      can [:edit, :update, :update_logo, :user_permissions,
           :webconference_options, :disable, :edit_recording], Space do |space|
        resource_enabled?(space) &&
          space.admins.include?(user)
      end

      # Join Requests

      # normal users can request membership
      # admins in a space can invite users
      can [:create], JoinRequest do |jr|
        is_space_and_enabled?(jr.group)
      end

      # users that created a join request can do a few things over it
      can [:show, :decline], JoinRequest do |jr|
        is_space_and_enabled?(jr.group) &&
          jr.group.try(:is_a?, Space) && jr.try(:candidate) == user
      end

      # users can accept invitations they received, space admins can accept requests
      # made to that space.
      can :accept, JoinRequest do |jr|
        group = jr.group
        if group.try(:is_a?, Space)
          is_space_and_enabled?(jr.group) &&
            ((jr.is_invite? && jr.try(:candidate) == user) ||
             (jr.is_request? && group.admins.include?(user)))
        else
          false
        end
      end

      # space admins can list requests and invite new members
      can [:index_join_requests, :index_news, :invite], Space do |s|
        resource_enabled?(s) &&
          s.admins.include?(user)
      end

      # space admins can work with all join requests in the space
      can [:show, :create, :decline], JoinRequest do |jr|
        group = jr.group
        is_space_and_enabled?(group) &&
          group.admins.include?(user)
      end

      # Posts
      # TODO: maybe space admins should be able to alter posts
      can :read, Post, space: { public: true, disabled: false }
      can [:read, :create, :reply_post], Post do |post|
        resource_enabled?(post.space) &&
          post.space.users.include?(user)
      end
      can [:read, :reply_post, :edit, :update, :destroy], Post, author_id: user.id, space: { disabled: false }

      # News
      # Only admins can create/alter news, the rest can only read
      # note: :show because :index is only for space admins
      can :show, News, space: { public: true, disabled: false }
      can :show, News do |news|
        resource_enabled?(news.space) &&
          news.space.users.include?(user)
      end
      can :manage, News do |news|
        resource_enabled?(news.space) &&
          news.space.admins.include?(user)
      end

      # Attachments
      can :manage, Attachment do |attach|
        resource_enabled?(attach.space) &&
          attach.space.admins.include?(user)
      end
      can [:read, :create], Attachment do |attach|
        resource_enabled?(attach.space) &&
          attach.space.users.include?(user)
      end
      can [:destroy], Attachment do |attach|
        resource_enabled?(attach.space) &&
          attach.space.users.include?(user) &&
          attach.author_id == user.id
      end
      can :read, Attachment, space: { public: true, disabled: false }

      # Permissions
      # Only space admins can update user roles/permissions
      can [:read, :edit, :update], Permission do |perm|
        case perm.subject_type
        when "Space"
          if resource_enabled?(perm.subject)
            admins = perm.subject.admins
          else
            admins = []
          end
        else
          admins = []
        end
        admins.include?(user)
      end

      # Events from MwebEvents
      if Mconf::Modules.mod_loaded?('events')
        def event_can_be_managed_by(event, user)
          case event.owner_type
          when 'User' then
            event.owner_id == user.id
          when 'Space' then
            resource_enabled?(event.owner) &&
              (!user.permissions.where(subject_type: 'MwebEvents::Event',
                role_id: Role.find_by_name('Organizer'), subject_id: event.id).empty? ||
               !user.permissions.where(subject_type: 'Space', subject_id: event.owner_id,
                role_id: Role.find_by_name('Admin')).empty?)
          end
        end

        can [:select, :read], MwebEvents::Event do |e|
          resource_enabled?(e.owner)
        end

        # Create events if they have a nil owner or are owned by a space you admin
        can :create, MwebEvents::Event do |e|
          e.owner.nil? || event_can_be_managed_by(e, user)
        end

        can [:edit, :update, :destroy, :invite, :send_invitation], MwebEvents::Event do |e|
          event_can_be_managed_by(e, user)
        end

        can :register, MwebEvents::Event do |e|
          enabled = e.owner_type == "Space" ? is_space_and_enabled?(e.owner) : true
          enabled &&
            MwebEvents::Participant.where(owner_id: user.id, event_id: e.id).empty? &&
            (e.public || (e.owner_type == 'Space' && e.owner.users.include?(user)))
        end

        # Participants from MwebEvents
        can :show, MwebEvents::Participant do |p|
          p.event.owner == user || p.owner == user
        end

        can [:edit, :update, :destroy], MwebEvents::Participant do |p|
          event_can_be_managed_by(p.event, user)
        end

        can [:index, :create], MwebEvents::Participant do |p|
          p.event.owner_type == "Space" ? is_space_and_enabled?(p.event.owner) : true
        end
      end
    end

    private

    # Abilities for the resources from BigbluebuttonRails.
    # Not everything is done here, some authorization steps are done by the gem
    # BigbluebuttonRails itself.
    # These actions have a difference from most of the other resources: most of them are only
    # accessible by admins, including standard actions such as `:show`, `:edit`, and `:index`.
    # However, normal users also have access to limited version of these actions, such as a page
    # to edit just a few attributes of a room or a recording. The methods for these actions are
    # in controllers other than the standard controllers for these resources (e.g.
    # BigbluebuttonRoomsController) and are named differently to differ than from the standard
    # actions (e.g. `:space_show` is a limited version of `:show` for rooms in spaces).
    def abilities_for_bigbluebutton_rails(user)

      # Can do the actions below if he's the owner or if he belongs to the space (with any role)
      # that owns the room.
      # `:create_meeting` is a custom name, not an action that exists in the controller
      can [:join_options, :create_meeting, :fetch_recordings,
           :invitation, :send_invitation], BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          user_is_owner_or_belongs_to_rooms_space(user, room)
      end

      # For user rooms only the owner can end meetings.
      # In spaces only the admins and the person that started the meeting can end it.
      can :end, BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          user_can_end_meeting(user, room)
      end

      # Users can recording meetings in their rooms, but only if they have the record flag set.
      # `:record_meeting` is a custom name, not an action that exists in the controller
      can :record_meeting, BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          user.can_record && user_is_owner_or_belongs_to_rooms_space(user, room)
      end

      # Currently only user rooms can be updated
      can :update, BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          room.owner_type == "User" && room.owner.id == user.id
      end

      # some actions in rooms should be accessible to any logged user
      # some of them will do the authorization themselves (e.g. permissions for :join
      # will change depending on the user and the target room)
      can [:invite, :invite_userid, :running, :join, :join_mobile], BigbluebuttonRoom do |room|
        resource_enabled?(room.owner) &&
          (room.owner_type == "User" || room.owner_type == "Space")
      end

      # a user can play recordings of his own room or recordings of
      # rooms of either public spaces or spaces he's a member of
      can :play, BigbluebuttonRecording do |recording|
        user_is_member_of_recordings_space(user, recording) ||
          recordings_space_is_public(recording) ||
          user_is_owner_of_recording(user, recording)
      end

      # a user can edit his recordings and recordings in spaces where he's an admin
      can :update, BigbluebuttonRecording do |recording|
        user_is_owner_of_recording(user, recording) ||
          user_is_admin_of_recordings_space(user, recording)
      end

      # a user can see and edit his recordings
      can [:user_show, :user_edit], BigbluebuttonRecording do |recording|
        user_is_owner_of_recording(user, recording)
      end

      # admins can edit recordings in their spaces
      can [:space_edit], BigbluebuttonRecording do |recording|
        user_is_admin_of_recordings_space(user, recording)
      end

      # recordings can be viewed in spaces if the space is public or the user belongs to the space
      can [:space_show], BigbluebuttonRecording do |recording|
        user_is_member_of_recordings_space(user, recording) ||
          recordings_space_is_public(recording)
      end
    end

    # Whether `user` is the owner of `room` of belongs to the space that owns `room`.
    def user_is_owner_or_belongs_to_rooms_space(user, room)
      if (room.owner_type == "User" && room.owner.id == user.id)
        true
      elsif (room.owner_type == "Space")
        space = Space.find(room.owner.id)
        space.users.include?(user)
      else
        false
      end
    end

    # Whether `user` can end the meeting in `room`.
    def user_can_end_meeting(user, room)
      if (room.owner_type == "User" && room.owner.id == user.id)
        true
      elsif (room.owner_type == "Space")
        space = Space.find(room.owner.id)
        if space.admins.include?(user)
          true
        elsif room.user_created_meeting?(user)
          true
        else
          false
        end
      else
        false
      end
    end

    # Whether `user` owns the room that owns `recording`.
    def user_is_owner_of_recording(user, recording)
      response = false
      unless recording.room.nil?
        if recording.room.owner_type == "User" && recording.room.owner_id == user.id
          response = true
        end
      end
      response
    end

    # Whether the user is an admin of the space that owns the room that owns `recording`.
    def user_is_admin_of_recordings_space(user, recording)
      response = false
      unless recording.room.nil?
        if recording.room.owner_type == "Space"
          space = Space.find(recording.room.owner_id)
          response = space.admins.include?(user)
        end
      end
      response
    end

    # Whether the user is a member of the space that owns the room that owns `recording`.
    def user_is_member_of_recordings_space(user, recording)
      response = false
      unless recording.room.nil?
        if recording.room.owner_type == "Space"
          space = Space.find(recording.room.owner_id)
          response = space.users.include?(user)
        end
      end
      response
    end

    # Whether the space that owns the room that owns `recording` is public.
    def recordings_space_is_public(recording)
      recording.room.try(:public?)
    end
  end

end
