# frozen_string_literal: true

# name: group-subgroup-automation
# about: Automate group membership via parent and subgroups
# version: 0.0.1
# authors: Dylan Henrich

enabled_site_setting :group_subgroup_automation_enabled

after_initialize do
  reloadable_patch do
    if defined?(DiscourseAutomation)
      on(:user_added_to_group) do |user, group|

        #When a user is added to a subgroup
        DiscourseAutomation::Automation
          .where(enabled: true, trigger: "user_added_to_subgroup")
          .find_each do |automation|
          fields = automation.serialized_fields
          group_ids = fields.dig("subgroups", "value")
          if group.id.in?(group_ids)
            automation.trigger!(
              "kind" => "user_added_to_subgroup",
              "usernames" => [user.username],
              "group" => group,
              "placeholders" => {
                "group_name" => group.name,
              },
            )
          end
        end
        #When a user is added to a parent group
        DiscourseAutomation::Automation
          .where(enabled: true, trigger: "user_added_to_parent_group")
          .find_each do |automation|
          fields = automation.serialized_fields
          group_id = fields.dig("parent_group", "value")
          if group.id == group_id
            automation.trigger!(
              "kind" => "user_added_to_parent_group",
              "usernames" => [user.username],
              "group" => group,
              "placeholders" => {
                "group_name" => group.name,
              },
            )
          end
        end
      end

      DiscourseAutomation::Triggerable::USER_ADDED_TO_SUBGROUP = "user_added_to_subgroup"
      add_automation_triggerable(DiscourseAutomation::Triggerable::USER_ADDED_TO_SUBGROUP) do
        field :subgroups, component: :groups, required: true
      end
      DiscourseAutomation::Triggerable::USER_ADDED_TO_PARENT_GROUP = "user_added_to_parent_group"
      add_automation_triggerable(DiscourseAutomation::Triggerable::USER_ADDED_TO_PARENT_GROUP) do
        field :parent_group, component: :group, required: true
      end

      on(:user_removed_from_group) do |user, group|
        DiscourseAutomation::Automation
          .where(enabled: true, trigger: "user_removed_from_subgroup")
          .find_each do |automation|
          fields = automation.serialized_fields
          group_ids = fields.dig("subgroups", "value")
          if group.id.in?(group_ids)
            automation.trigger!(
              "kind" => "user_removed_from_subgroup",
              "usernames" => [user.username],
              "group" => group,
              "placeholders" => {
                "group_name" => group.name,
              },
            )
          end
        end

        DiscourseAutomation::Automation
          .where(enabled: true, trigger: "user_removed_from_parent_group")
          .find_each do |automation|
          fields = automation.serialized_fields
          group_id = fields.dig("parent_group", "value")
          if group.id == group_id
            automation.trigger!(
              "kind" => "user_removed_from_parent_group",
              "usernames" => [user.username],
              "group" => group,
              "placeholders" => {
                "group_name" => group.name,
              },
            )
          end
        end
      end

      DiscourseAutomation::Triggerable::USER_REMOVED_FROM_SUBGROUP = "user_removed_from_subgroup"
      add_automation_triggerable(DiscourseAutomation::Triggerable::USER_REMOVED_FROM_SUBGROUP) do
        field :subgroups, component: :groups, required: true
      end
      DiscourseAutomation::Triggerable::USER_REMOVED_FROM_PARENT_GROUP = "user_removed_from_parent_group"
      add_automation_triggerable(DiscourseAutomation::Triggerable::USER_REMOVED_FROM_PARENT_GROUP) do
        field :parent_group, component: :group, required: true
      end


      DiscourseAutomation::Scriptable::ADD_USER_TO_PARENT_GROUP = "add_user_to_parent_group"
      add_automation_scriptable(
        DiscourseAutomation::Scriptable::ADD_USER_TO_PARENT_GROUP
      ) do
        field :parent_group, component: :group, required: true
        triggerables [:user_added_to_subgroup]
        script do |context, fields|
          username = context["usernames"][0]
          parent_group = fields.dig("parent_group", "value")
          group = Group.find(parent_group)
          user = User.find_by(username: username)
          if group && user
            group.add(user)
            GroupActionLogger.new(Discourse.system_user, group).log_add_user_to_group(user)
          end
        end
      end

      DiscourseAutomation::Scriptable::REMOVE_USER_FROM_PARENT_GROUP = "remove_user_from_parent_group"
      add_automation_scriptable(
        DiscourseAutomation::Scriptable::REMOVE_USER_FROM_PARENT_GROUP
      ) do
        field :parent_group, component: :group, required: true
        triggerables [:user_removed_from_subgroup]
        script do |context, fields|
          username = context["usernames"][0]
          parent_group_id = fields.dig("parent_group", "value")
          group = Group.find(parent_group_id)
          user = User.find_by(username: username)
          subgroup_ids = fields.dig("subgroups", "value")
          if group && user
            other_subgroup_memberships = GroupUser.where(user_id: user.id, group_id: subgroup_ids).pluck(:group_id)
            if other_subgroup_memberships.empty? && group.remove(user)
              GroupActionLogger.new(Discourse.system_user, group).log_remove_user_from_group(user)
            end
          end
        end
      end

      DiscourseAutomation::Scriptable::ADD_USER_TO_SUBGROUPS = "add_user_to_subgroups"
      add_automation_scriptable(
        DiscourseAutomation::Scriptable::ADD_USER_TO_SUBGROUPS
      ) do
        field :subgroups, component: :groups, required: true
        triggerables [:user_added_to_parent_group]
        script do |context, fields|
          username = context["usernames"][0]
          subgroup_ids = fields.dig("subgroups", "value")
          parent_group_id = fields.dig("parent_group", "value")
          group = Group.find(parent_group_id)
          user = User.find_by(username: username)
          if group && user
            other_subgroup_memberships = GroupUser.where(user_id: user.id, group_id: subgroup_ids).pluck(:group_id)
            subgroups_to_add = subgroup_ids - other_subgroup_memberships
            subgroups_to_add.each do |subgroup_id|
              subgroup = Group.find(subgroup_id)
              subgroup.add(user)
              GroupActionLogger.new(Discourse.system_user, subgroup).log_add_user_to_group(user)
           end
          end
        end
      end

      DiscourseAutomation::Scriptable::REMOVE_USER_FROM_SUBGROUPS = "remove_user_from_subgroups"
      add_automation_scriptable(
        DiscourseAutomation::Scriptable::REMOVE_USER_FROM_SUBGROUPS
      ) do
        field :subgroups, component: :groups, required: true
        triggerables [:user_removed_from_parent_group]
        script do |context, fields|
          username = context["usernames"][0]
          subgroup_ids = fields.dig("subgroups", "value")
          parent_group_id = fields.dig("parent_group", "value")
          group = Group.find(parent_group_id)
          user = User.find_by(username: username)
          if group && user
            other_subgroup_memberships = GroupUser.where(user_id: user.id, group_id: subgroup_ids).pluck(:group_id)
            subgroups_to_remove = other_subgroup_memberships & subgroup_ids
            subgroups_to_remove.each do |subgroup_id|
              subgroup = Group.find(subgroup_id)
              subgroup.remove(user)
              GroupActionLogger.new(Discourse.system_user, subgroup).log_remove_user_from_group(user)
            end
          end
        end
      end
    end
  end
end
