defmodule Koda.Email do
  import Swoosh.Email
  alias Koda.Mailer

  defp cfg(k), do: Application.get_env(:koda, :email)[k]
  defp from_field, do: {cfg(:from_name), cfg(:from_address)}

  def send_verification(user, code) do
    new()
    |> from(from_field())
    |> to({user.username, user.email})
    |> subject("Verify your Koda account")
    |> html_body(verification_html(user.username, code))
    |> text_body("Hi #{user.username},\n\nYour Koda verification code is: #{code}\n\nExpires in 60 minutes.\n\n-- Koda | #{cfg(:app_url)}")
    |> Mailer.deliver()
  end

  def send_password_reset(user, code) do
    new()
    |> from(from_field())
    |> to({user.username, user.email})
    |> subject("Reset your Koda password")
    |> html_body(reset_html(user.username, code))
    |> text_body("Hi #{user.username},\n\nYour password reset code is: #{code}\n\nExpires in 15 minutes.\n\nIf you didn't request this, ignore this email.\n\n-- Koda")
    |> Mailer.deliver()
  end

  def send_welcome(user) do
    new()
    |> from(from_field())
    |> to({user.username, user.email})
    |> subject("Welcome to Koda Alpha")
    |> html_body(welcome_html(user.username))
    |> text_body("Welcome to Koda, #{user.username}!\n\nYour account is verified. Your messages are end-to-end encrypted.\n\n-- Koda | #{cfg(:app_url)}")
    |> Mailer.deliver()
  end

  defp base(title, body) do
    """
    <!DOCTYPE html><html><head><meta charset="UTF-8">
    <style>
    body{font-family:-apple-system,sans-serif;background:#f4f5f7;margin:0;padding:0}
    .w{max-width:520px;margin:32px auto;padding:0 16px}
    .card{background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,.08)}
    .hdr{background:linear-gradient(135deg,#7B68EE,#5BEAD4);padding:28px 32px;text-align:center}
    .hdr-mark{display:inline-block;width:44px;height:44px;background:rgba(255,255,255,.2);border-radius:11px;font-size:22px;font-weight:800;color:#fff;line-height:44px}
    .hdr-name{color:#fff;font-size:18px;font-weight:700;margin-top:8px}
    .bdy{padding:28px 32px}
    h1{font-size:20px;color:#0d0e1a;margin:0 0 12px}
    p{font-size:14px;color:#4a4f6a;margin:0 0 14px;line-height:1.6}
    .code-box{background:#f0eefb;border:2px solid #c8c1f5;border-radius:10px;text-align:center;padding:18px;margin:20px 0}
    .code{font-family:monospace;font-size:32px;font-weight:800;color:#7B68EE;letter-spacing:10px}
    .code-lbl{font-size:11px;color:#8890b0;margin-top:6px;text-transform:uppercase;letter-spacing:.08em}
    .ftr{background:#f8f9fc;border-top:1px solid #e8eaf2;padding:16px 32px;text-align:center}
    .ftr p{font-size:11px;color:#9ba5c8;margin:0}
    .ftr a{color:#7B68EE;text-decoration:none;font-size:11px}
    </style></head><body>
    <div class="w"><div class="card">
    <div class="hdr"><div class="hdr-mark">K</div><div class="hdr-name">Koda</div></div>
    <div class="bdy">#{body}</div>
    <div class="ftr">
    <p><a href="#{cfg(:terms_url)}">Terms</a> &nbsp;&middot;&nbsp; <a href="#{cfg(:privacy_url)}">Privacy</a> &nbsp;&middot;&nbsp; <a href="mailto:#{cfg(:support)}">Support</a></p>
    <p style="margin-top:6px">&copy; 2024 GryphonHeart LLC &mdash; <a href="#{cfg(:app_url)}">koda.fyi</a></p>
    </div>
    </div></div></body></html>
    """
  end

  defp verification_html(username, code) do
    base("Verify your Koda account", """
    <h1>Verify your email</h1>
    <p>Hi #{username}, enter this code in the Koda app to verify your email:</p>
    <div class="code-box">
      <div class="code">#{code}</div>
      <div class="code-lbl">Expires in 60 minutes</div>
    </div>
    <p style="font-size:12px;color:#9ba5c8">If you didn't create a Koda account, you can safely ignore this email.</p>
    """)
  end

  defp reset_html(username, code) do
    base("Reset your Koda password", """
    <h1>Password reset</h1>
    <p>Hi #{username}, here is your password reset code:</p>
    <div class="code-box">
      <div class="code">#{code}</div>
      <div class="code-lbl">Expires in 15 minutes</div>
    </div>
    <p style="font-size:12px;color:#9ba5c8">If you didn't request this, no changes were made to your account.</p>
    """)
  end

  defp welcome_html(username) do
    base("Welcome to Koda Alpha", """
    <h1>Welcome, #{username}!</h1>
    <p>Your account is verified and ready. Koda encrypts your messages on your device before they leave &mdash; we can't read them, and neither can anyone else.</p>
    <p>Create a server, invite your squad, and start talking privately.</p>
    <p style="font-size:12px;color:#9ba5c8">Questions? <a href="mailto:#{cfg(:support)}">#{cfg(:support)}</a></p>
    """)
  end
end
