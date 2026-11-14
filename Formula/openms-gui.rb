class OpenmsGui < Formula
  desc "Graphical applications (TOPPView, TOPPAS, INIFileEditor) of OpenMS"
  homepage "https://openms.de/"
  # The GUI layer of OpenMS, built from OpenMS-TOPP-GUI against the installed libopenms.
  # BEGIN nightly-source (managed by .github/scripts/bump-nightly.py)
  url "https://github.com/OpenMS/OpenMS-TOPP-GUI/archive/1c7ee164d1d69035544403656f1cc5afc08fbd76.tar.gz"
  version "3.7.0-pre.20261113"
  sha256 "bc9b3d1d417a6db494bec40cd0e1593db6a66da052dc6d00ea7daf2ae0cb93c4"
  # END nightly-source
  license "BSD-3-Clause"
  head "https://github.com/OpenMS/OpenMS-TOPP-GUI.git", branch: "develop"

  livecheck do
    skip "Pinned to the OpenMS-TOPP-GUI develop branch by .github/workflows/nightly.yml"
  end

  bottle do
    root_url "https://ghcr.io/v2/openms/openms"
    sha256 cellar: :any, arm64_tahoe:  "9bd9a8b4c4f3b7ad597d25a75078bae49caf17043f2669d10fe3f71403f3d6cb"
    sha256 cellar: :any, x86_64_linux: "ed3aa3f5eab705f7813dd32a0bbb881c5c72838102d40ea668deb6bd490c8f95"
  end

  # Built against libopenms, which must have exactly the version of OpenMS-TOPP-GUI.
  depends_on "boost" => :build
  depends_on "cmake" => :build
  depends_on "openms/openms/libopenms"
  depends_on "openms/openms/openms" # TOPPView and TOPPAS run the TOPP tools
  depends_on "qtbase"
  depends_on "qtdeclarative"
  depends_on "qtpositioning"
  depends_on "qtsvg"
  depends_on "qtwebchannel"
  depends_on "qtwebengine"

  on_macos do
    depends_on "libomp"
  end

  def install
    args = %W[
      -DCMAKE_BUILD_TYPE=Release
      -DOpenMS_DIR=#{formula_opt_lib("openms/openms/libopenms")}/cmake/OpenMS
      -DENABLE_DOCS=OFF
      -DENABLE_TUTORIALS=OFF
      -DGIT_TRACKING=OFF
      -DHAS_XSERVER=OFF
      -DENABLE_CLASS_TESTING=OFF
      -DENABLE_TOPP_TESTING=OFF
      -DENABLE_PIPELINE_TESTING=OFF
      -DCMAKE_INSTALL_RPATH=#{rpath(source: libexec/"bin")};#{formula_opt_lib("openms/openms/libopenms")}
    ]
    args << "-DOpenMP_ROOT=#{formula_opt_prefix("libomp")}" if OS.mac?
    args += ccache_args

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # openms is keg-only, so lay the GUI out as a merged OpenMS installation in libexec, where the
    # applications find the TOPP tools and both tool registries relative to themselves:
    #   libexec/bin                  GUI tools plus links to all TOPP tools
    #   libexec/share/OpenMS/TOOLS   OpenMS-GUI.tsv plus a link to OpenMS-TOPP.tsv
    #   libexec/<App>.app (macOS)    bundles look in ../../../bin and ../../../share/OpenMS/TOOLS
    # Only the GUI entry points are exposed in bin.
    openms = Formula["openms/openms/openms"]
    libexec.install bin
    (libexec/"share/OpenMS").install share/"OpenMS/TOOLS"
    (libexec/"share/OpenMS/TOOLS").install_symlink openms.opt_share/"OpenMS/TOOLS/OpenMS-TOPP.tsv"
    (libexec/"bin").install_symlink openms.opt_bin.children

    apps = %w[TOPPView TOPPAS INIFileEditor]
    apps.each do |app|
      if OS.mac?
        # App bundles may not live in bin; their RPATH (@executable_path/../../../../lib) still reaches lib.
        libexec.install libexec/"bin/#{app}.app"
        (prefix/"Applications").install_symlink libexec/"#{app}.app"
        bin.write_exec_script libexec/"#{app}.app/Contents/MacOS/#{app}"
      else
        bin.write_exec_script libexec/"bin/#{app}"
      end
    end
    %w[ExecutePipeline ImageCreator].each { |tool| bin.write_exec_script libexec/"bin/#{tool}" }
  end

  # Opt-in compiler cache for this tap's CI (see .github/workflows/tests.yml).
  # Not used for regular `brew install` and dropped when upstreaming to homebrew-core.
  def ccache_args
    ccache = ENV.fetch("HOMEBREW_OPENMS_CCACHE", "")
    cache_dir = ENV.fetch("HOMEBREW_OPENMS_CCACHE_DIR", "")
    return [] if ccache.empty? || cache_dir.empty? || !File.executable?(ccache)

    ENV["CCACHE_DIR"] = cache_dir
    ENV["CCACHE_BASEDIR"] = buildpath.to_s
    ENV["CCACHE_NOHASHDIR"] = "1"
    ENV["CCACHE_COMPILERCHECK"] = "%compiler% --version"
    ENV["CCACHE_SLOPPINESS"] = "time_macros,include_file_mtime,include_file_ctime,pch_defines"
    ENV["CCACHE_MAXSIZE"] = ENV.fetch("HOMEBREW_OPENMS_CCACHE_MAXSIZE", "5G")
    %W[-DCMAKE_C_COMPILER_LAUNCHER=#{ccache} -DCMAKE_CXX_COMPILER_LAUNCHER=#{ccache}]
  end

  def caveats
    return unless OS.mac?

    <<~EOS
      To add the applications to Launchpad/Finder:
        ln -sf #{opt_prefix}/Applications/*.app /Applications/
    EOS
  end

  test do
    ENV["QT_QPA_PLATFORM"] = "offscreen"
    assert_path_exists libexec/"share/OpenMS/TOOLS/OpenMS-GUI.tsv"
    assert_path_exists libexec/"share/OpenMS/TOOLS/OpenMS-TOPP.tsv"
    %w[TOPPView TOPPAS INIFileEditor ExecutePipeline ImageCreator].each do |app|
      assert_predicate bin/app, :executable?
    end
    # TOPP tools are reachable from the GUI's tool directory.
    assert_match "OpenMS Version", shell_output("#{libexec}/bin/OpenMSInfo")

    system bin/"ImageCreator", "-write_ini", "ImageCreator.ini"
    assert_match "ImageCreator", (testpath/"ImageCreator.ini").read
  end
end
