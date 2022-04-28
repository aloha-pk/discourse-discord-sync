require 'time'

# Class that will run all sync jobs
class Util

  # Create {'forum group'=> 'discord role'} ALOHA_MAP
  ALOHA_MAP = { 
    'staff-big-kahuna'=> "big kahuna", 
    'staff-manager'=> "manager", 
    'staff-sysadmin'=> "sysadmin", 
    'staff-admin'=> "admin",
    'staff-moderator'=> "moderator", 
    'staff-guard'=> "guard", 
    'staff-all'=> "staff", 
    'staff-retired'=> "retiree", 
    'staff-inactive'=> "",
    'staff-mc-manager'=> "mc-manager", 
    'staff-mc-admin'=> "mc-admin", 
    'staff-mc-moderator'=> "mc-moderator", 
    'staff-mc-guard'=> "mc-guard",
    'staff-mc-all'=> "mc-staff", 
    'player-mc'=> "mc-player", 
    'developer'=> "developer", 
    'news-team'=> "news-team", 
    'news-team-leaders'=> "",
    'player-trusted'=> "trusted", 
    'kamaaina'=> "kamaaina", 
    'donor'=> "", 
    'amr'=> "amr", 
    'aos-developer'=> "aos-developer", 
    'aos-modder'=> "aos-modder",
    'aos-mapmaker'=> "", 
    'photographer'=> "photographer",
    'event'=> "event" # dynamic for all event groups; handled in sync_user()
  }

  # Search for a role in the Discord server with a given Discourse group name
  def self.find_role(forum_group)
    discord_role = nil
    discord_role_name = ALOHA_MAP[forum_group]
    # if role exists, fetch discord role
    if discord_role_name then
      Instance::bot.servers.each do |key, server|
        server.roles.each do |role|
          if role.name == discord_role_name then
            discord_role = role
          end
        end
      end
    end
    # return role, or nil if it doesn't exist in ALOHA_MAP
    discord_role
  end

  # Method triggered to sync user on Discord server join
  def self.sync_from_discord(discord_id)
    # search for users with the given Discord UD
    builder = DB.build("select u.* from user_associated_accounts uaa, users u /*where*/ limit 1")
    builder.where("provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = u.id")
    builder.where("uaa.provider_uid = :discord_id", discord_id: discord_id)
    result = builder.query
    # if forum account found
    if result.size != 0 then
      # process and sync the user using the standard Discourse method
      result.each do |t|
        self.sync_user(t)
      end
    end
  end  

  # Sync users from Discourse to Discord
  def self.sync_user(user)
    discord_id = nil
    # fetch the Discord ID from database
    builder = DB.build("select uaa.provider_uid from user_associated_accounts uaa /*where*/ limit 1")
    builder.where("provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = :user_id", user_id: user.id)
    builder.query.each do |t|
      discord_id = t.provider_uid
    end

    unless discord_id.nil? then
      current_discord_roles = []
      discord_roles = []
      forum_groups = []

      if SiteSetting.discord_debug_enabled then
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Attempting role sync on: #{discord_id}")
      end

      # get user groups from database and populate discord_roles
      builder = DB.build("select g.name from groups g, group_users gu /*where*/")
      builder.where("g.id = gu.group_id")
      builder.where("gu.user_id = :user_id", user_id: user.id)
      builder.query.each do |t|
        forum_groups << t.name
        discord_roles << self.find_role(t.name)
      end
      
      if SiteSetting.discord_debug_enabled then
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Fetched forum groups: #{forum_groups}")
      end
      
      # For each server, just keep things synced
      Instance::bot.servers.each do |key, server|
        member = server.member(discord_id)
        unless member.nil? then

          # Make nickname the same as Discourse username, if setting is enabled
          if member.nick != user.username && SiteSetting.discord_sync_username then
            Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Updated nickname @#{user.username}")
            member.set_nick(user.username)
          end

          # If there is a verified role set, grant the user with that role
          if SiteSetting.discord_sync_verified_role != "" then
            role = self.find_role(SiteSetting.discord_sync_verified_role)
            unless role.nil? then
              # if debug enabled, print the verified role being added to user
              if SiteSetting.discord_debug_enabled then
                Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Adding verified role: #{role.name}")
              end
              # add verified role to roles to be added to user
              discord_roles << role
            end
          end  

          # Add event role to user if they're in dynamically named/created aloha.pk event group
          if forum_groups.any? { |group| group.include? 'event-'} then
            discord_roles << self.find_role('event')
            if SiteSetting.discord_debug_enabled then
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Adding event role.")
            end
          end

          # Populate current_discord_roles and ensure sync_safe roles are added to the user, if they currently have them. 
          server.roles.each do |role|       
            if (member.role? role) && (role.name != "@everyone") then                     
              current_discord_roles << role
              # if the role is included in sync_safe_roles
              if (SiteSetting.discord_sync_safe_roles.include? role.name) then
                # if debug enabled, print the sync_safe role being added to user
                if SiteSetting.discord_debug_enabled then
                  Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Adding sync_safe role: #{role.name}")
                end
                # add sync_safe role to roles to be added to user
                discord_roles << role
              end
            end
          end          

          # If debug enabled, print list of current roles the user has before sync
          if SiteSetting.discord_debug_enabled then
            current_discord_roles -= [nil, '']
            current_discord_roles.sort_by(&:name)
            roles_string = current_discord_roles.map(&:name).join(', ')
            Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: @#{user.username} roles before sync: #{roles_string}")
          end          

          # Just in case
          discord_roles -= [nil, '']
          discord_roles.sort_by(&:name)

          # Add all roles which the user is a part of
          member.set_roles(discord_roles)
          # Print notification to admin channel          
          roles_string = discord_roles.map(&:name).join(', ')             
          Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Set @#{user.username} roles to #{roles_string}") 
          # Print notification to public channel
          self.build_send_public_message()      
        end
      end      
    end
  end

  # Build and send a formatted message to the public channel
  def self.build_send_public_message()
    # TODO properly format and beautify role sync public message
  end

  # Sync groups from Discourse to Discord
  def self.sync_groups_and_roles()
    # TODO for each group,
    # fetch forum group color and set discord role color
    # fetch forum group icon pic and set dicord role icon
  end

end