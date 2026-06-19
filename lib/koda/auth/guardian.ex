defmodule Koda.Auth.Guardian do
  use Guardian, otp_app: :koda

  alias Koda.Repo
  alias Koda.Auth.User

  def subject_for_token(%User{id: id}, _claims), do: {:ok, id}
  def subject_for_token(_, _), do: {:error, :unknown_resource_type}

  def resource_from_claims(%{"sub" => id}) do
    case Repo.get(User, id) do
      nil  -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :missing_sub}
end
