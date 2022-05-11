require 'discordrb'

# Handler to detect new members in a server
module NewMember
  extend Discordrb::EventContainer

  # Sync users when a new user joins the server
  member_join do |event|
    Util.sync_from_discord(event.user.id)
  end
end

# Container for the initialized bot
module Instance
  @@bot = nil

  def self.init
    @@bot = Discordrb::Commands::CommandBot.new token: SiteSetting.discord_sync_token, prefix: SiteSetting.discord_sync_prefix
    @@bot
  end

  def self.bot
    @@bot
  end
end

# Main bot class
class Bot
  def self.run_bot
    bot = Instance::init

    unless bot.nil?
      # Register the new member handler
      bot.include! NewMember

      bot.ready do |event|
        puts "Logged in as #{bot.profile.username} (ID:#{bot.profile.id}) | #{bot.servers.size} servers"
        Instance::bot.send_message(SiteSetting.discord_sync_admin_channel_id, "aloha.pk sync bot started!")
      end

      # Add a simple command to confirm everything works properly
      bot.command(:ping) do |event|
        event.respond 'Pong!'
      end

      # Add a simple command to trigger Group -> Role sync
      bot.command(:sync) do |event|
        if event.channel.id == SiteSetting.discord_sync_admin_channel_id then
          event.respond 'Starting Group -> Role sync!'
          Util.sync_groups_and_roles()
          event.respond 'Completed Group -> Role sync!'
        end
      end

      bot.run
    end
  end
end
