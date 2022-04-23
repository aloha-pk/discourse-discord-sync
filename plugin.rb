# name: Discord Sync
# about: Sync a Discord server with a Discourse community
# version: 1.0
# authors: Diego Barreiro, FerrariFlunker
# url: https://github.com/aloha-pk/discourse-discord-sync

gem 'rbnacl', '3.4.0'
gem 'event_emitter', '0.2.6'
gem 'websocket', '1.2.8'
gem 'websocket-client-simple', '0.3.0'
gem 'opus-ruby', '1.0.1', { require: false }
gem 'netrc', '0.11.0'
gem 'mime-types-data', '3.2019.1009'
gem 'mime-types', '3.3.1'
gem 'domain_name', '0.5.20180417'
gem 'http-cookie','1.0.3'
gem 'http-accept', '1.7.0', { require: false }
gem 'rest-client', '2.1.0.rc1'

gem 'discordrb-webhooks', '3.3.0', {require: false}
gem 'discordrb', '3.4.1', git: "https://github.com/shardlab/discordrb"


enabled_site_setting :discord_sync_enabled

after_initialize do

  require_dependency File.expand_path('../lib/bot.rb', __FILE__)
  require_dependency File.expand_path('../lib/utils.rb', __FILE__)

  bot_thread = Thread.new do
    begin
      Bot.run_bot
    rescue Exception => ex
      Rails.logger.error("Discord Bot: There was a problem: #{ex}")
    end
  end

  # Sync user (and groups) on update (usually username)
  User.class_eval do
    after_save do |user|
      if user.id > 0 then Util.sync_user(user) end
      Util.sync_groups_and_roles()
    end
  end

  # Sync user (and groups) on group join
  DiscourseEvent.on(:user_added_to_group) do |user, group, automatic|
    if user.id > 0 then Util.sync_user(user) end
    Util.sync_groups_and_roles()
  end

  # Sync user (and groups) on group removal
  DiscourseEvent.on(:user_removed_from_group) do |user, group|
    if user.id > 0 then Util.sync_user(user) end
    Util.sync_groups_and_roles()
  end

  # Sync user (and groups) after authenticating with Discord
  #DiscourseEvent.on(:after_auth) do |authenticator, auth_result|
  #  if authenticator.name == "discord" && auth_result.user.id > 0 then Util.sync_user(auth_result.user) end
  #  Util.sync_groups_and_roles()
  #end

  STDERR.puts '--------------------------------------------------'
  STDERR.puts '!Discord-Sync Bot spawned, say "!ping" on Discord!'
  STDERR.puts '--------------------------------------------------'
  STDERR.puts '(-------      If not check logs          --------)'
end
