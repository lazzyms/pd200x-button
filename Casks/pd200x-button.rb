cask "pd200x-button" do
  version :latest
  sha256 :no_check

  url "https://github.com/lazzyms/pd200x-button/releases/latest/download/pd200x-button-macos-latest.zip"
  name "PD200X Button"
  desc "Menu bar app that turns the PD200X mute button into a dictation control"
  homepage "https://github.com/lazzyms/pd200x-button"

  depends_on macos: ">= :ventura"

  app "PD200X Button.app"

  caveats <<~EOS
    Launch PD200X Button from Applications after install.
    If macOS warns that the app is from an unidentified developer, use
    right-click -> Open the first time you launch it.
  EOS
end
