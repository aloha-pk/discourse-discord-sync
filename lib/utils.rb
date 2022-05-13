require 'time'
require 'date'

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
    'staff-inactive'=> "inactive-staff",
    'staff-mc-manager'=> "mc-manager", 
    'staff-mc-admin'=> "mc-admin", 
    'staff-mc-moderator'=> "mc-moderator", 
    'staff-mc-guard'=> "mc-guard",
    'staff-mc-all'=> "mc-staff", 
    'player-mc'=> "mc-player", 
    'developer'=> "developer", 
    'news-team'=> "news-team", 
    'news-team-leaders'=> "news-team-leaders",
    'player-trusted'=> "trusted", 
    'kamaaina'=> "kamaaina", 
    'donor'=> "donor",
    'backer'=>"donor", 
    'amr'=> "amr",
    'aes'=> "aes", 
    'aos-developer'=> "aos-developer", 
    'aos-modder'=> "aos-modder",
    'aos-mapmaker'=> "aos-mapmaker", 
    'photographer'=> "photographer",
    'event'=> "event" # dynamic for all event groups; handled in sync_user()
  }

  # Create an inverted version of ALOHA_MAP - {'discord role'=> 'forum group'}
  ALOHA_MAP_INVERT = ALOHA_MAP.invert()

  # Create array of messages for member sync alerts.
  PUBLIC_PING_MESSAGES = [
    "Heads up, %s!",
    "%s, think fast!",
    "Hey you. Yes, you %s. Your attention is required!",
    "Look over here, %s!",
    "This is for you, %s!",
    "Urgent message for: %s!",
    "You've been synced, %s!",
    "Attention %s!",
    "For you, %s!",
    "%s officially synced!",
    "I made this ping for you, %s!",
    "Hello there, %s.  You've been synced!",
    "Sync? Done. %s!",
    "Synced %s!",
    "Pinging %s!",
    "Take a look at this, %s!",
    "Sync notification for: %s!",
    "Notifying %s of sync!",
    "Sync alert for: %s!",
    "Alerting %s of sync!",
    "Holy moly, %s has been synced!",
    "Woah, %s has been synced!",
    "Wow, %s has been synced!"
  ]

  # Search for a role in the Discord server with a given Discourse group name
  # @param forum group name string
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

  # Search for a group on the forum given a Discourse group name
  # @param forum group name string
  def self.find_group(discord_role)
    forum_group = nil
    forum_group_name = ALOHA_MAP_INVERT[discord_role]
    if forum_group_name then
      # search for group with the given forum group name
      builder = DB.build("select g.* from groups g /*where*/")
      builder.where("g.name = :forum_group_name", forum_group_name: forum_group_name)
      # if group found, set it to forum_group
      (builder.query || []).each do |t|
        forum_group = t
      end
    end
    # return group, or nil if it doesn't exist on forum
    forum_group
  end

  # Method triggered to sync user on Discord server join
  # @param Discord ID of user or member
  def self.sync_from_discord(discord_id)
    # search for users with the given Discord UD
    builder = DB.build("select u.* from user_associated_accounts uaa, users u /*where*/ limit 1")
    builder.where("provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = u.id")
    builder.where("uaa.provider_uid = :discord_id", discord_id: discord_id)
    # if forum account found
    (builder.query || []).each do |t|
      # process and sync the user using the standard Discourse method
      self.sync_user(t)      
    end
  end  

  # Sync users from Discourse to Discord
  # @param aloha.pk forum user
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

      # if the user is in the sync disabled group, do not sync the user
      unless forum_groups.any? { |group| group.include? SiteSetting.discord_sync_disabled_group} then
      
        # For each server, just to keep things synced
        Instance::bot.servers.each do |key, server|
          member = server.member(discord_id, true, true)
          unless member.nil? then

            if SiteSetting.discord_debug_enabled then
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Using discordrb version: #{Discordrb::VERSION}")
            end

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
            member.roles.each do |role|       
              if role.name != "@everyone" then                     
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
              current_discord_roles.sort_by!(&:name)
              roles_string = current_discord_roles.map(&:name).join(', ')
              Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: @#{user.username} roles before sync: #{roles_string}")
            end          

            # Just in case
            discord_roles -= [nil, '']
            discord_roles.sort_by!(&:name)

            # Add all roles which the user is a part of
            member.set_roles(discord_roles)
            # Print notification to admin channel          
            roles_string = discord_roles.map(&:name).join(', ')             
            Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Set @#{user.username} roles to #{roles_string}") 
            # Print notification to public channel
            self.build_send_public_messages(member, discord_roles - current_discord_roles, current_discord_roles - discord_roles)      
          end
        end
      end      
    end
  end

  # Build and send formatted messages to the public channel
  # @param member being synced
  # @param Array<Role> being added
  # @param Array<Role> being removed
  def self.build_send_public_messages(member, roles_added, roles_removed)    
    channel = Instance::bot.channel(SiteSetting.discord_sync_public_channel_id)
    unless channel.nil? then
      # send debug message if enabled
      if SiteSetting.discord_debug_enabled then       
        roles_added_string = roles_added.map(&:name).join(', ')
        roles_removed_string = roles_removed.map(&:name).join(', ')
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: @#{member.name}- Added: #{roles_added_string}  Removed: #{roles_removed_string}")
      end
      #for each role added to the user, send embedded message
      roles_added.each do |role|
        channel.send_embed do |embed|
          embed.title = "The #{role.name} role has been added to #{member.name}!"
          embed.description = "Click [here](#{SiteSetting.discord_sync_role_support_url}) to learn how to add or remove an aloha.pk role!"
          embed.color = role.color
          embed.timestamp = Time.now
          embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "aloha.pk", icon_url: SiteSetting.discord_sync_message_footer_logo_url)
        end
      end
      #for each role removed from the user, send embedded message
      roles_removed.each do |role|
        channel.send_embed do |embed|
          embed.title = "The #{role.name} role has been removed from #{member.name}!"
          embed.description = "Click [here](#{SiteSetting.discord_sync_role_support_url}) to learn how to add or remove an aloha.pk role!"
          embed.color = role.color
          embed.timestamp = Time.now
          embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "aloha.pk", icon_url: SiteSetting.discord_sync_message_footer_logo_url)
        end
      end
      if !roles_added.empty? || !roles_removed.empty? then
        Instance::bot.send_message(SiteSetting.discord_sync_public_channel_id, PUBLIC_PING_MESSAGES.sample % member.mention)
      end
    end
  end

  # Sync groups from Discourse to Discord
  def self.sync_groups_and_roles()
    synced_roles = []
    # for each server, just to keep things synced
    Instance::bot.servers.each do |key, server|
      server.roles.each do |role|
        group = self.find_group(role.name)        
        # if group found
        unless group.nil? then
          if SiteSetting.discord_debug_enabled then
            Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Attempting group -> role sync on: #{group.name}")
          end
          # set role color
          role_color = (group.flair_bg_color || '969c9f')
          role.color = Discordrb::ColourRGB.new(role_color)  
          # set role icon
          icon_name = (group.flair_icon || 'user')
          path = File.expand_path("../icons/#{icon_name}.png", __dir__)
          unless File.file? path then
            path = File.expand_path("../icons/user.png", __dir__)
          end
          role.icon = File.open(path, 'rb')      
          # add role to synced_roles
          synced_roles << role 
        end
      end
    end    
    # if debug enabled, print list of roles that were synced
    if SiteSetting.discord_debug_enabled then
      synced_roles -= [nil, '']
      roles_string = synced_roles.map(&:name).join(', ')
      Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Synced roles: #{roles_string}")
    end
  end

end