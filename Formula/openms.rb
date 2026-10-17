class Openms < Formula
  desc "Command-line tools (TOPP) for LC-MS/MS data analysis"
  homepage "https://openms.de/"
  # BEGIN nightly-source (managed by .github/scripts/bump-nightly.py)
  url "https://github.com/OpenMS/OpenMS/archive/1868c06d04c517f85e45e8584a5f6875d0eac1bc.tar.gz"
  version "3.7.0-pre.20261016"
  sha256 "29ea38614083a259c25540425db0aef48279aae0d4f5f3bff3e20d36333447a0"
  # END nightly-source
  license "BSD-3-Clause"
  head "https://github.com/OpenMS/OpenMS.git", branch: "develop"

  livecheck do
    skip "Pinned to the OpenMS nightly branch by .github/workflows/nightly.yml"
  end

  bottle do
    root_url "https://ghcr.io/v2/openms/openms"
    sha256 cellar: :any, arm64_tahoe:  "50703b9cb188fa8fa81b6c125ad4e984e7a66b4297bfa1573d882d20757e7e4f"
    sha256 cellar: :any, x86_64_linux: "652271c9c01e1a992abc3c9eef23f219bb93530beffd07f1c8f09d5e9c23020c"
  end

  keg_only "it installs about 150 tools with generic names (e.g. `FileInfo`) that clash with other formulae"

  # Built against libopenms, which must come from the very same source tarball.
  depends_on "boost" => :build
  depends_on "cmake" => :build
  depends_on "nlohmann-json" => :build
  depends_on "openms/openms/libopenms"

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
      -DBUILD_TOPP_TOOLS=ON
      -DWITH_GUI=OFF
      -DUSE_EXTERNAL_JSON=ON
    ]
    args << "-DOpenMP_ROOT=#{formula_opt_prefix("libomp")}" if OS.mac?
    args += ccache_args

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
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
    # Keg-only: the tools find their registry relative to themselves (bin/../share/OpenMS/TOOLS).
    assert_match "OpenMS Version", shell_output("#{bin}/OpenMSInfo")

    (testpath/"test.mgf").write <<~EOS
      BEGIN IONS
      TITLE=test
      PEPMASS=500.25
      CHARGE=2+
      RTINSECONDS=60
      100.1 10
      200.2 20
      300.3 30
      END IONS
    EOS
    system bin/"FileConverter", "-in", "test.mgf", "-out", "test.mzML"
    assert_match "Number of spectra: 1", shell_output("#{bin}/FileInfo -in test.mzML")
  end
end
