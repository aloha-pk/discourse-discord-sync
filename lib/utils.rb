# Class that will run all sync jobs
class Util

  # Search for a role in the server with a given name
  def self.find_role(role_name)
    discord_role = nil
    Instance::bot.servers.each do |key, server|
      server.roles.each do |role|
        if role.name == role_name then
          discord_role = role
        end
      end
    end
    discord_role
  end

  # Method triggered to sync user on Discord server join
  def self.sync_from_discord(discord_id)
    # Search for users with the given Discord UD
    builder = DB.build("select u.* from user_associated_accounts uaa, users u /*where*/ limit 1")
    builder.where("provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = u.id")
    builder.where("uaa.provider_uid = :discord_id", discord_id: discord_id)

    result = builder.query

    # If forum account found
    if result.size != 0 then

      # Process and sync the user using the standard Discourse method
      result.each do |t|
        self.sync_user(t)
      end

    end
  end  

  # Sync users from Discourse to Discord
  def self.sync_user(user)
    discord_id = nil

    # Fetch the Discord ID from database
    builder = DB.build("select uaa.provider_uid from user_associated_accounts uaa /*where*/ limit 1")
    builder.where("provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = :user_id", user_id: user.id)
    builder.query.each do |t|
      discord_id = t.provider_uid
    end

    unless discord_id.nil? then
      groups = []

      # Get user groups from database
      builder = DB.build("select g.name from groups g, group_users gu /*where*/")
      builder.where("g.visibility_level = :visibility", visibility: 0)
      builder.where("g.id = gu.group_id")
      builder.where("gu.user_id = :user_id", user_id: user.id)
      builder.query.each do |t|
        groups << t.name
      end
      
      # For each server, just keep things synced
      Instance::bot.servers.each do |key, server|
        member = server.member(discord_id)
        unless member.nil? then

          # Make nickname the same as Discourse username, if setting is enabled
          if member.nick != user.username && SiteSetting.discord_sync_username then
            Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "Updated nickname @#{user.username}")
            member.set_nick(user.username)
          end

          # If there is a verified role set, grant the user with that role
          if SiteSetting.discord_sync_verified_role != "" then
            role = self.find_role(SiteSetting.discord_sync_verified_role)
            unless role.nil? || (member.role? role) then
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "@#{user.username} granted role #{role.name}")
              member.add_role(role)
            end
          end

          # Remove all roles which are not safe, not the verified role or the user is not part of a group with that name
          member.roles.each do |role|
            unless (groups.include? role.name) || (SiteSetting.discord_sync_safe_roles.include? role.name) || role.name == SiteSetting.discord_sync_verified_role then
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "@#{user.username} removed role #{role.name}")
              member.remove_role(role)
            end
          end

          # Add all roles which the user is part of a group
          groups.each do |group|
            role = self.find_role(group)
            unless role.nil? || (member.role? role) then
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "@#{user.username} granted role #{role.name}")
              member.add_role(role)
            end
          end

        end
      end      
    end
  end

  #Sync groups from Discourse to Discord
  def self.sync_groups_and_roles()
    #to:do
    #create (forum, discord) map
    #fetch forum group color and set discord role color
    #fetch forum group icon pic and set dicord role icon
  end

end