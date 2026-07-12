defmodule KodaWeb.Router do
  use KodaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug Koda.Auth.Pipeline
  end

  # -- Public routes ----------------------------------------------------------
  scope "/api/v1", KodaWeb do
    pipe_through :api

    # Auth
    post "/auth/register",         AuthController, :register
    post "/auth/login",            AuthController, :login
    post "/auth/password/reset",   AuthController, :request_password_reset
    post "/auth/password/confirm", AuthController, :confirm_password_reset
    post "/auth/verify_email",     AuthController, :verify_email

    # Server discovery (public -- no auth needed)
    get  "/discover",              DiscoverController, :index
    get  "/invite/:code",          InviteController,   :show

    # LiveKit webhook (signed by LiveKit, not user JWT)
    post "/livekit/webhook",       LiveKitWebhookController, :webhook
  end

  # -- Protected routes -------------------------------------------------------
  scope "/api/v1", KodaWeb do
    pipe_through [:api, :auth]

    # Auth
    delete "/auth/logout",                  AuthController, :logout
    get    "/auth/me",                      AuthController, :me
    post   "/auth/password/force_change",   AuthController, :force_change_password
    post   "/auth/verify_email/resend",     AuthController, :resend_verification
    post   "/auth/totp/setup",              AuthController, :totp_setup

    # Key bundles (E2EE / KCP)
    put    "/keys/bundle",              KeyBundleController, :put
    get    "/keys/bundle/status",       KeyBundleController, :status
    get    "/keys/bundle/:user_id",     KeyBundleController, :get

    # TEMPORARY -- remove once Scylla connection issue is resolved
    post   "/auth/totp/verify",             AuthController, :totp_verify
    get    "/auth/keys",                    AuthController, :get_keys
    put    "/auth/keys",                    AuthController, :upload_keys
    get    "/users/:id/keys",               AuthController, :get_user_keys

    # User settings
    get    "/users/me/settings",            UserController, :get_settings
    patch  "/users/me/settings",            UserController, :update_settings
    patch  "/users/me",                     UserController, :update_profile

     # Uploads
    post   "/uploads",                      UploadController, :upload

    # Servers
    get    "/servers",                      ServerController, :index
    post   "/servers",                      ServerController, :create
    get    "/servers/:id",                  ServerController, :show
    patch  "/servers/:id",                  ServerController, :update
    delete "/servers/:id",                  ServerController, :delete
    get    "/servers/:id/members",          ServerController, :members
    delete "/servers/:server_id/members",   ServerController, :leave

    # Channels
    get    "/servers/:server_id/channels",  ChannelController, :index
    post   "/servers/:server_id/channels",  ChannelController, :create
    patch  "/channels/:id",                 ChannelController, :update
    delete "/channels/:id",                 ChannelController, :delete

    # Gallery
    get    "/channels/:channel_id/gallery/collections",           GalleryController, :list_collections
    post   "/channels/:channel_id/gallery/collections",           GalleryController, :create_collection
    patch  "/gallery/collections/:id",                            GalleryController, :update_collection
    delete "/gallery/collections/:id",                            GalleryController, :delete_collection
    get    "/channels/:channel_id/gallery/posts",                 GalleryController, :list_posts
    post   "/channels/:channel_id/gallery/posts",                 GalleryController, :create_post
    get    "/gallery/collections/:collection_id/posts",           GalleryController, :list_collection_posts
    delete "/gallery/posts/:id",                                  GalleryController, :delete_post

    # Categories (channel groupings)
    get    "/servers/:server_id/categories", CategoryController, :index
    post   "/servers/:server_id/categories", CategoryController, :create
    patch  "/categories/:id",                CategoryController, :update
    delete "/categories/:id",                CategoryController, :delete

    # Roles
    get    "/servers/:server_id/roles",                  RoleController, :index
    post   "/servers/:server_id/roles",                  RoleController, :create
    patch  "/roles/:id",                                 RoleController, :update
    delete "/roles/:id",                                 RoleController, :delete
    post   "/members/:member_id/roles/:role_id",         RoleController, :assign
    delete "/members/:member_id/roles/:role_id",         RoleController, :unassign

    # Moderation
    delete "/channels/:channel_id/messages/:message_id", ModerationController, :delete_message
    delete "/servers/:server_id/members/:user_id/kick",  ModerationController, :kick_member
    post   "/servers/:server_id/members/:user_id/ban",   ModerationController, :ban_member
    delete "/servers/:server_id/members/:user_id/ban",   ModerationController, :unban_member
    get    "/servers/:server_id/bans",                   ModerationController, :list_bans

    # Messages
    get    "/channels/:channel_id/messages",ChannelController, :messages
    post   "/channels/:channel_id/messages",ChannelController, :send_message
    post   "/channels/:channel_id/typing",  ChannelController, :typing

    # Voice
    get    "/channels/:channel_id/voice/token",        VoiceController, :token
    get    "/channels/:channel_id/voice/participants",  VoiceController, :participants
    get    "/voice/self_test_token",                    VoiceController, :self_test_token
    
    # Stage channels
    post   "/channels/:channel_id/stage/join",               StageController, :join
    post   "/channels/:channel_id/stage/raise_hand",         StageController, :raise_hand
    post   "/channels/:channel_id/stage/lower_hand",         StageController, :lower_hand
    post   "/channels/:channel_id/stage/grant/:user_id",     StageController, :grant_speaker
    delete "/channels/:channel_id/stage/grant/:user_id",     StageController, :revoke_speaker

    # Invites
    get    "/servers/:server_id/invites",   InviteController, :index
    post   "/servers/:server_id/invites",   InviteController, :create
    post   "/invite/:code/join",            InviteController, :join
    delete "/invites/:id",                  InviteController, :delete

    # Direct messages
    get    "/dms/conversations",            DmController, :list_conversations
    post   "/dms/conversations",            DmController, :open_conversation
    get    "/dms/:conversation_id/messages",DmController, :messages
    post   "/dms/:conversation_id/messages",DmController, :send_message

    # Notifications
    get    "/notifications",                NotificationController, :index
    post   "/notifications/:id/read",       NotificationController, :mark_read
    post   "/notifications/read_all",       NotificationController, :mark_all_read

    # Friends
    get    "/friends",                      FriendController, :index
    post   "/friends/request",              FriendController, :send_request
    post   "/friends/:id/accept",           FriendController, :accept
    delete "/friends/users/:user_id",       FriendController, :remove
    post   "/friends/:user_id/block",       FriendController, :block
  end
end