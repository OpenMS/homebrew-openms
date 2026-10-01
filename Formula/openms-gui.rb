class OpenmsGui < Formula
  desc "Graphical applications (TOPPView, TOPPAS, INIFileEditor) of OpenMS"
  homepage "https://openms.de/"
  # BEGIN nightly-source (managed by .github/scripts/bump-nightly.py)
  url "https://github.com/OpenMS/OpenMS/archive/e25ac614f495ce1e4933f46b41da18199eeba3ef.tar.gz"
  version "3.7.0-pre.20260930"
  sha256 "b049502cc14c5665141e4407acc983bda64d11e548143f9ba8879d48b0512290"
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
      -DCMAKE_INSTALL_RPATH=#{rpath};#{formula_opt_lib("openms/openms/libopenms")}
      -DBUILD_TOPP_TOOLS=OFF
      -DWITH_GUI=ON
    ]
    args << "-DOpenMP_ROOT=#{formula_opt_prefix("libomp")}" if OS.mac?
    args += ccache_args

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    return unless OS.mac?

    # App bundles may not live in bin. prefix/Applications keeps the bundles' RPATH
    # (@executable_path/../../../../lib) pointing at lib; wrappers make them callable.
    %w[TOPPView TOPPAS INIFileEditor].each do |app|
      (prefix/"Applications").install bin/"#{app}.app"
      bin.write_exec_script prefix/"Applications/#{app}.app/Contents/MacOS/#{app}"
    end
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

  test do
    ENV["QT_QPA_PLATFORM"] = "offscreen"
    ENV["OPENMS_TOOL_REGISTRY_PATH"] = share/"OpenMS/TOOLS"
    assert_path_exists share/"OpenMS/TOOLS/OpenMS-GUI.tsv"
    %w[TOPPView TOPPAS INIFileEditor].each do |app|
      assert_predicate bin/app, :executable?
    end

    system bin/"ImageCreator", "-write_ini", "ImageCreator.ini"
    assert_match "ImageCreator", (testpath/"ImageCreator.ini").read
  end
end
