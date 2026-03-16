class SwiftuiRender < Formula
  desc "Headless SwiftUI renderer -- render views to PNG from the command line"
  homepage "https://github.com/nicklama/swiftui-render"
  url "https://github.com/nicklama/swiftui-render/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "PLACEHOLDER"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/swiftui-render"

    # Generate and install shell completions
    output = Utils.safe_popen_read(bin/"swiftui-render", "--generate-completion-script", "bash")
    (bash_completion/"swiftui-render").write output
    output = Utils.safe_popen_read(bin/"swiftui-render", "--generate-completion-script", "zsh")
    (zsh_completion/"_swiftui-render").write output
    output = Utils.safe_popen_read(bin/"swiftui-render", "--generate-completion-script", "fish")
    (fish_completion/"swiftui-render.fish").write output
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/swiftui-render --version")
  end
end
