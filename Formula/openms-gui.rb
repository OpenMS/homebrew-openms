class OpenmsGui < Formula
  desc "Graphical applications (TOPPView, TOPPAS, INIFileEditor) of OpenMS"
  homepage "https://openms.de/"
  # BEGIN nightly-source (managed by .github/scripts/bump-nightly.py)
  url "https://github.com/OpenMS/OpenMS/archive/fe7b9cc0e51cd4ac85b96f17ad2c3493d004a4db.tar.gz"
  version "3.7.0-pre.20261005"
  sha256 "90bd868116c89dad33c62330ab174b610b11f2b8e6878b5087c69cdd9c9bfb5b"
  # END nightly-source
  license "BSD-3-Clause"
  head "https://github.com/OpenMS/OpenMS.git", branch: "develop"

  livecheck do
    skip "Pinned to the OpenMS nightly branch by .github/workflows/nightly.yml"
  end

  # Built against libopenms, which must come from the very same source tarball.
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
      -DOPENMS_USE_INSTALLED_LIBRARY=ON
      -DOpenMS_DIR=#{formula_opt_lib("openms/openms/libopenms")}/cmake/OpenMS
      -DPYOPENMS=OFF
      -DENABLE_DOCS=OFF
      -DENABLE_UPDATE_CHECK=OFF
      -DGIT_TRACKING=OFF
      -DHAS_XSERVER=OFF
      -DENABLE_CLASS_TESTING=OFF
      -DENABLE_TOPP_TESTING=OFF
      -DENABLE_PIPELINE_TESTING=OFF
      -DCMAKE_INSTALL_RPATH=#{rpath(source: libexec/"bin")};#{formula_opt_lib("openms/openms/libopenms")}
      -DBUILD_TOPP_TOOLS=OFF
      -DWITH_GUI=ON
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
