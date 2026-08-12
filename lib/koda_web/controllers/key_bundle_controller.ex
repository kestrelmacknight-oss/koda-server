defmodule KodaWeb.KeyBundleController do
  use KodaWeb, :controller
  alias Koda.Crypto

  def upsert(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    case Crypto.upsert_key_bundle(user.id, params) do
      {:ok, bundle} -> json(conn, %{ok: true, id: bundle.id})
      {:error, cs}  -> conn |> put_status(422) |> json(%{error: inspect(cs.errors)})
    end
  end

  def show(conn, %{"user_id" => user_id}) do
    case Crypto.get_key_bundle(user_id) do
      nil    -> conn |> put_status(404) |> json(%{error: "No key bundle found"})
      bundle -> json(conn, %{
        user_id:     user_id,
        ik_sign_pub: bundle.ik_sign_pub,
        ik_dh_pub:   bundle.ik_dh_pub,
        spk_pub:     bundle.spk_pub,
        spk_sig:     bundle.spk_sig,
        opks:        bundle.opks
      })
    end
  end

  def status(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    has_bundle = Crypto.get_key_bundle(user.id) != nil
    json(conn, %{has_bundle: has_bundle})
  end
end
