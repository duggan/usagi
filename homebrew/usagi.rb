# Reference cask. The actual file lives in the homebrew-usagi tap repo.
# Update version + sha256 + url after each release.

cask "usagi" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/rossduggan/usagi/releases/download/v#{version}/Usagi-#{version}.dmg"
  name "usagi"
  desc "Minimalist Claude usage tracker for the macOS menu bar"
  homepage "https://github.com/rossduggan/usagi"

  depends_on macos: ">= :sonoma"

  app "Usagi.app"

  zap trash: [
    "~/Library/Preferences/ie.duggan.usagi.plist",
    "~/Library/Application Support/Usagi",
  ]
end
