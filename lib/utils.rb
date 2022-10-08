require 'time'
require 'date'

# Class that will run all sync jobs
class Util

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

  ALOHA_SERVER_ID = 109793081594806272
  USER_LAST_SYNCED = Hash.new(0)  

  # Method triggered to sync user on Discord event
  # @param Discord ID of user or member
  def self.sync_from_discord(discord_id)
    # check if user was synced within the past x seconds, to prevent looping syncs and unnecessary DB calls
    if (Time.now.to_i - USER_LAST_SYNCED[discord_id]) > 2 then
      # search for users with the given Discord ID
      builder = DB.build("SELECT u.* FROM user_associated_accounts uaa, users u /*where*/ limit 1")
      builder.where("uaa.provider_name = :provider_name", provider_name: "discord")
      builder.where("uaa.user_id = u.id")
      builder.where("uaa.provider_uid = :discord_id", discord_id: discord_id)
      # if forum account found
      (builder.query || []).each do |user|
        # process and sync the user using the standard Discourse method
        self.sync_user(user)      
      end
    end
  end
  
  # Unsync user on Discord
  # @param aloha.pk forum user
  def self.unsync_user(user)
    member = nil
    removed_roles = []
    aloha_server = Instance::bot.servers[ALOHA_SERVER_ID]

    builder = DB.build("SELECT uaa.provider_uid FROM user_associated_accounts uaa /*where*/ limit 1")
    builder.where("uaa.provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = :user_id", user_id: user.id)
    builder.query.each do |row|
      member = aloha_server.member(row.provider_uid, true, true)  
    end

    unless member.nil? then
      if SiteSetting.discord_debug_enabled then
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, 
          "#{Time.now.utc.iso8601}: Attempting role unsync on: #{member.nickname}")
      end

      member.roles.each do |role|
        # if the role isn't included in sync_safe_roles, remove it       
        if (role.name != "@everyone") && (!SiteSetting.discord_sync_safe_roles.include? role.name) then                     
          removed_roles << role
        end
      end

      # Just in case
      removed_roles -= [nil, '']
      removed_roles.sort_by!(&:name)

      # Remove roles
      member.remove_role(removed_roles)            

      # Print notification to admin channel          
      roles_string = removed_roles.map(&:name).join(', ')             
      Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Removed #{roles_string} role(s) from @#{user.username}") 
      # Print notification to public channel
      self.build_send_public_messages(member, [], removed_roles) 
      
      # Update hashmap to keep track of when user was last synced
      USER_LAST_SYNCED[discord_id] = Time.now.to_i
    end
  end  

  # Sync users from Discourse to Discord
  # @param aloha.pk forum user
  def self.sync_user(user)
    discord_id = nil
    current_discord_roles = []
    discord_roles = []
    forum_groups = []
    aloha_server = Instance::bot.servers[ALOHA_SERVER_ID]
    
    # get user's forum groups (and corresponding discord role IDs) and user's discord id
    builder = DB.build("SELECT uaa.provider_uid, g.name, g.discord_role_id 
      FROM groups g 
      JOIN group_users gu ON gu.group_id = g.id
      JOIN user_associated_accounts uaa ON uaa.user_id = gu.user_id
      /*where*/")
    builder.where("uaa.provider_name = :provider_name", provider_name: "discord")
    builder.where("uaa.user_id = :user_id", user_id: user.id)
    builder.query.each do |row|
      discord_id = row.provider_uid
      forum_groups << row.name
      discord_roles << aloha_server.role(row.discord_role_id)
    end

    unless discord_id.nil? then      

      if SiteSetting.discord_debug_enabled then
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, 
          "#{Time.now.utc.iso8601}: Attempting role sync on: #{discord_id}, with forum groups: #{forum_groups}")
      end

      # if the user is in the sync disabled group, do not sync the user
      unless forum_groups.any? { |group| group.include? SiteSetting.discord_sync_disabled_group} then              
        
          member = aloha_server.member(discord_id, true, true)
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
              role = aloha_server.role(SiteSetting.discord_sync_verified_role)
              unless role.nil? then
                # if debug enabled, print the verified role being added to user
                if SiteSetting.discord_debug_enabled then
                  Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Adding verified role: #{role.name}")
                end
                # add verified role to roles to be added to user
                discord_roles << role
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
            
            # Update hashmap to keep track of when user was last synced
            USER_LAST_SYNCED[discord_id] = Time.now.to_i
          end
        end
      end      
    end
  end  

  # Sync groups from Discourse to Discord
  def self.sync_groups_to_roles()
    synced_roles = []
    aloha_server = Instance::bot.servers[ALOHA_SERVER_ID]
    builder = DB.build("SELECT g.* FROM groups g WHERE g.discord_role_id IS NOT NULL")
    builder.query.each do |group|
      role = aloha_server.role(group.discord_role_id)        
      # if group found
      unless role.nil? then
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
    # if debug enabled, print list of roles that were synced
    if SiteSetting.discord_debug_enabled then
      synced_roles -= [nil, '']
      roles_string = synced_roles.map(&:name).join(', ')
      Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "#{Time.now.utc.iso8601}: Synced roles: #{roles_string}")
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
      if !roles_added.empty? || !roles_removed.empty? then
        # check if user was synced within the past x seconds, to prevent unecessary pings
        if (Time.now.to_i - USER_LAST_SYNCED[discord_id]) > 60 then
          Instance::bot.send_message(SiteSetting.discord_sync_public_channel_id, PUBLIC_PING_MESSAGES.sample % member.mention)
        end
      end
      #for each role added to the user, send embedded message
      roles_added.each do |role|
        channel.send_embed do |embed|
          embed.title = "The #{role.name} role has been added to #{member.display_name}!"
          embed.description = "Visit our groups page [here](#{SiteSetting.discord_sync_role_support_url})!"
          embed.color = role.color
          embed.timestamp = Time.now
          embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "aloha.pk", icon_url: SiteSetting.discord_sync_message_footer_logo_url)
        end
      end
      #for each role removed from the user, send embedded message
      roles_removed.each do |role|
        channel.send_embed do |embed|
          embed.title = "The #{role.name} role has been removed from #{member.display_name}!"
          embed.description = "Visit our groups page [here](#{SiteSetting.discord_sync_role_support_url})!"
          embed.color = role.color
          embed.timestamp = Time.now
          embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: "aloha.pk", icon_url: SiteSetting.discord_sync_message_footer_logo_url)
        end
      end      
    end
  end

end