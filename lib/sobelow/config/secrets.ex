defmodule Sobelow.Config.Secrets do
  @moduledoc """
  # Hard-coded Secrets

  In the event of a source-code disclosure via file read
  vulnerability, accidental commit, etc, hard-coded secrets
  may be exposed to an attacker. This may result in
  database access, cookie forgery, and other issues.

  Sobelow detects missing hard-coded secrets by checking the prod
  configuration.

  Hard-coded secrets checks can be ignored with the following command:

      $ mix sobelow -i Config.Secrets
  """
  alias Sobelow.Config
  alias Sobelow.Utils
  use Sobelow.Finding
  @finding_type "Config.Secrets: Hardcoded Secret"

  def run(dir_path, configs) do
    Enum.each(configs, fn conf ->
      path = dir_path <> conf

      if conf != "config.exs" do
        Config.get_configs_by_file(:secret_key_base, path)
        |> enumerate_secrets(path)
      end

      Utils.get_fuzzy_configs("password", path)
      |> enumerate_fuzzy_secrets(path)

      Utils.get_fuzzy_configs("secret", path)
      |> enumerate_fuzzy_secrets(path)
    end)
  end

  defp enumerate_secrets(secrets, file) do
    Enum.each(secrets, fn {{_, [line: lineno], _} = fun, key, val} ->
      if is_binary(val) && String.length(val) > 0 && !is_env_var?(val) do
        add_finding(file, lineno, fun, key, val)
      end
    end)
  end

  defp enumerate_fuzzy_secrets(secrets, file) do
    Enum.each(secrets, fn {{_, [line: lineno], _} = fun, vals} ->
      Enum.each(vals, fn {k, v} ->
        if is_binary(v) && String.length(v) > 0 && !is_env_var?(v) do
          add_finding(file, lineno, fun, k, v)
        end
      end)
    end)
  end

  def is_env_var?("${" <> rest) do
    String.ends_with?(rest, "}")
  end

  def is_env_var?(_), do: false

  defp add_finding(file, line_no, fun, key, val) do
    vuln_line_no = get_vuln_line(file, line_no, val)

    file_path = Utils.normalize_path(file)
    file_header = "File: #{file_path}"
    line_header = "Line: #{vuln_line_no}"
    key_header = "Key: #{key}"

    case Sobelow.get_env(:format) do
      "json" ->
        finding = [
          type: @finding_type,
          file: file_path,
          line: vuln_line_no,
          key: key
        ]

        Sobelow.log_finding(finding, :high)

      "txt" ->
        Sobelow.log_finding(@finding_type, :high)

        Utils.print_custom_finding_metadata(fun, :highlight_all, :high, @finding_type, [
          file_header,
          line_header,
          key_header
        ])

      "compact" ->
        Utils.log_compact_finding(vuln_line_no, @finding_type, file, :high)

      _ ->
        Sobelow.log_finding(@finding_type, :high)
    end
  end

  defp get_vuln_line(file, config_line_no, secret) do
    {_, secrets} =
      File.read!(file)
      |> String.replace("\"#{secret}\"", "@sobelow_secret")
      |> Code.string_to_quoted()
      |> Macro.prewalk([], &get_vuln_line/2)

    Enum.find(secrets, config_line_no, &(&1 > config_line_no))
  end

  defp get_vuln_line({:@, [line: line_no], [{:sobelow_secret, _, _}]} = ast, acc) do
    {ast, [line_no | acc]}
  end

  defp get_vuln_line(ast, acc), do: {ast, acc}
end
