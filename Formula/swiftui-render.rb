class SwiftuiRender < Formula
  desc "Headless SwiftUI renderer -- render views to PNG from the command line"
  homepage "https://github.com/olliewagner/swiftui-render"
  head "https://github.com/olliewagner/swiftui-render.git", branch: "main"
  url "https://github.com/olliewagner/swiftui-render.git", tag: "v0.2.0"
  version "0.2.0"
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
