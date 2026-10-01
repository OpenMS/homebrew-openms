class Openms < Formula
  desc "C++ library and command-line tools (TOPP) for LC-MS/MS data analysis"
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

  depends_on "cmake" => :build
  depends_on "apache-arrow"
  depends_on "boost"
  depends_on "eigen"
  depends_on "highs"
  depends_on "libsvm"
  depends_on "libzip"
  depends_on "nlohmann-json"
  depends_on "onnxruntime"
  depends_on "sqlite"
  depends_on "sqlitecpp"
  depends_on "xerces-c"
  depends_on "zstd"

  uses_from_macos "bzip2"
  uses_from_macos "curl"
  uses_from_macos "libxml2"

  on_macos do
    depends_on "libomp"
  end

  on_linux do
    depends_on "zlib-ng-compat"
  end

  # Everything below is fetched by OpenMS' CMake at configure time. Pinning it
  # here keeps the build offline and reproducible (required for homebrew-core).
  # BEGIN nightly-resources (managed by .github/scripts/bump-nightly.py)
  resource "opentims" do
    url "https://github.com/michalsta/opentims/archive/refs/tags/v1.2.0b4.tar.gz"
    sha256 "f722dd4c4c4e6d1db31fb649c621da5daa2707d0dac716bf2618a0f5dd5c58e8"
  end

  resource "pylmcf" do
    url "https://github.com/michalsta/pylmcf/archive/refs/tags/v0.9.8.tar.gz"
    sha256 "4be32d9aadc6f7deab64bd0fede04d936f581eca758d2330ac08c86a7ffcce87"
  end

  resource "wnet" do
    url "https://github.com/michalsta/wnet/archive/refs/tags/v0.9.11.tar.gz"
    sha256 "3f5b91ecdb8c51276710007e1f8717d2bd897375f939699d6df147f2122d8c13"
  end

  resource "wnetalign" do
    url "https://github.com/michalsta/wnetalign/archive/refs/tags/v0.9.8.tar.gz"
    sha256 "26b270b483b71a195a96afd7a86c93100cbc500dff818a9baf7dd2e94354cde0"
  end

  resource "peptdeep_ccs_dynamic.onnx" do
    url "https://archive.openms.de/openms/models/peptdeep_ccs_dynamic.onnx"
    sha256 "41816f325cdd838897b7e7dcaf291da5d4d3903a1532fc5dc9db7e0725015801"
  end

  resource "peptdeep_ms2_dynamic.onnx" do
    url "https://archive.openms.de/openms/models/peptdeep_ms2_dynamic.onnx"
    sha256 "4141ea233d663b6f5b98ad80b8923ee685dae5cfdbe12243e2e30cd9c44ecf00"
  end

  resource "peptdeep_rt_dynamic.onnx" do
    url "https://archive.openms.de/openms/models/peptdeep_rt_dynamic.onnx"
    sha256 "3f3b847ea37a9333ac163409f3d4b343d021471548091c61aed6cfa398ce62fd"
  end
  # END nightly-resources

  def install
    fetchcontent_args = %w[opentims pylmcf wnet wnetalign].map do |name|
      resource(name).stage(buildpath/"deps"/name)
      "-DFETCHCONTENT_SOURCE_DIR_#{name.upcase}=#{buildpath}/deps/#{name}"
    end

    # OpenMS downloads the PeptDeep models into this directory unless files with
    # matching SHA256 are already present.
    models = buildpath/"build/src/openms/share/OpenMS/models"
    resources.select { |r| r.name.end_with?(".onnx") }.each do |r|
      r.stage { models.install Pathname.pwd.children.first => r.name }
    end

    args = %W[
      -DCMAKE_BUILD_TYPE=Release
      -DFETCHCONTENT_FULLY_DISCONNECTED=ON
      -DWITH_GUI=OFF
      -DWITH_ONNX=ON
      -DONNXRuntime_INCLUDE_DIR=#{formula_opt_include("onnxruntime")}/onnxruntime
      -DWITH_OPENTIMS=ON
      -DWITH_THERMO_RAW=OFF
      -DLP_SOLVER=HIGHS
      -DARROW_USE_STATIC=OFF
      -DUSE_EXTERNAL_SQLITECPP=ON
      -DPYOPENMS=OFF
      -DENABLE_DOCS=OFF
      -DENABLE_TDL=OFF
      -DENABLE_UPDATE_CHECK=OFF
      -DGIT_TRACKING=OFF
      -DHAS_XSERVER=OFF
      -DINSTALL_OPENMS_EXAMPLES=OFF
      -DENABLE_CLASS_TESTING=OFF
      -DENABLE_TOPP_TESTING=OFF
      -DENABLE_PIPELINE_TESTING=OFF
      -DCMAKE_INSTALL_RPATH=#{rpath}
    ] + fetchcontent_args
    args << "-DOpenMP_ROOT=#{formula_opt_prefix("libomp")}" if OS.mac?
    args += ccache_args

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # OpenMS may copy libonnxruntime next to libOpenMS; use Homebrew's instead.
    rm Dir[lib/"libonnxruntime*"]
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
    ENV["CCACHE_MAXSIZE"] = ENV.fetch("HOMEBREW_OPENMS_CCACHE_MAXSIZE", "3G")
    %W[-DCMAKE_C_COMPILER_LAUNCHER=#{ccache} -DCMAKE_CXX_COMPILER_LAUNCHER=#{ccache}]
  end

  test do
    assert_match "OpenMS Version", shell_output("#{bin}/OpenMSInfo")
    %w[peptdeep_ccs_dynamic.onnx peptdeep_ms2_dynamic.onnx peptdeep_rt_dynamic.onnx].each do |model|
      assert_path_exists share/"OpenMS/models"/model
    end

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
