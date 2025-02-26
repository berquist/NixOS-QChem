{ stdenv, lib, makeWrapper, requireFile, autoPatchelfHook, writeTextFile, perl, sysstat, zlib,
  glibc, gcc-unwrapped, which, less, more, coreutils,
  # Configuration
  useMPI ? false
}:
let
  systemName = if stdenv.isLinux && stdenv.isx86_64
    then "em64t-unknown-linux-gnu"
    else "x86_64-unknown-linux-gnu";

in stdenv.mkDerivation rec {
  version = "7.7";
  pname = "turbomole";

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = [
    zlib
    gcc-unwrapped.lib
    glibc
  ];

  propagatedBuildInputs = [
    perl
    sysstat
    which
  ];

  src = requireFile {
    sha256 = "b903ffb4fb9d1a1dbca81187f039df99c9fc22a4eefce5566db852da4991795d";
    name = "turbolinux${lib.replaceStrings ["."] [""] version}_TMG.tar.gz";
    url = "https://www.turbomole.org/";
  };

  postPatch = ''
    for f in Config_turbo_env Config_turbo_env.csh scripts mpirun_scripts mpirun_scripts/IMPI/intel64/lib; do
      patchShebangs $f
    done
  '';

  dontConfigure = true;
  dontBuild = true;

  /*
  Sets environment variables, that turbomole potentially uses.
  */
  TURBOMOLE_SYSNAME = systemName;
  PARA_ARCH = if useMPI then "MPI" else "SMP";

  /*
  Turbomole is too tightly coupled to its directory structure and i cannot really break it.
  Therefore try to clean as good as possible and put most stuff in share and symlink then to entry
  points.
  This roughly follows the ideas in Config_turbo_env
  */
  installPhase = ''
    runHook preInstall


    # Copy the entire installation to share/turbomole
    export TURBODIR=$out/share/turbomole
    mkdir -p $TURBODIR
    cp -r * $TURBODIR/.

    # The symlink/$0 magic of ridft. The script is actually a symlink to rdgrad and figures out
    # which fortran executable to call for an actual RIDFT calculation. Now they use
    # "PROG=`basename $0`", which gives "ridft", when the script is called by its symlink name,
    # but during wrapping it is not.
    unlink $TURBODIR/smprun_scripts/ridft
    cp $TURBODIR/smprun_scripts/rdgrad $TURBODIR/smprun_scripts/ridft
    substituteInPlace $TURBODIR/smprun_scripts/rdgrad \
      --replace 'export PROG=`basename $0`' "export PROG=rdgrad"
    substituteInPlace $TURBODIR/smprun_scripts/ridft \
      --replace 'export PROG=`basename $0`' "export PROG=ridft"

    # Find all executables which are entry points.
    exesBin=$(find $TURBODIR/bin/${TURBOMOLE_SYSNAME}_${lib.strings.toLower PARA_ARCH} -type l,f -executable)
    exesScript=$(find $TURBODIR/scripts/ -type f -executable)
    exes="$exesBin $exesScript"

    # Wrap up executables and link them to the bin directory.
    mkdir -p $out/bin
    for exe in $exes ; do
      ln -s $exe $out/bin/.
    done

    # Libraries should be available in the library directory
    mkdir -p $out/lib
    for i in $(find $TURBODIR/libso -type f); do
      ln -s $i $out/lib/.
    done

    runHook postInstall
  '';

  dontAutoPatchelf = true;
  noAuditTmpdir = true; # Patchelf segfaults on multiple files and crashes the build

  postFixup = let
    libSearchPath = lib.strings.makeSearchPath "lib" [
      "$out/lib"
      "$out/share/turbomole/libso/${systemName}_mpi"
      gcc-unwrapped.lib
      zlib
      glibc
    ];
  in ''
    # Patch elf dynamic library paths and interpreters
    for dir in $TURBODIR/libso $TURBODIR/bin/*; do
      files=$(find $dir -type f -executable -maxdepth 1 ! -name rimp2)
      for f in $files; do
        echo "Patching executable: $f: "
        patchelf \
          --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
          --set-rpath "${libSearchPath}"\
          $f
      done
    done


    exesToWrap="$(find $TURBODIR/bin -type f -executable) $(find $TURBODIR/scripts -type f -executable -maxdepth 1) $(find $TURBODIR/smprun_scripts -type f -executable ! -name "*.so*") $(find $TURBODIR/mpirun_scripts -type f -executable ! -name "*.so*")"
    for exe in $exesToWrap; do
      echo "Wrapping exe: $exe"
      wrapProgram $exe \
        --prefix PATH : "${which}/bin" \
        --prefix PATH : "${coreutils}/bin" \
        --prefix PATH : "${less}/bin" \
        --prefix PATH : "${more}/bin" \
        --set PAGER "more" \
        --set TURBODIR "$TURBODIR" \
        --set PARA_ARCH "${PARA_ARCH}" \
        --set TURBOARCH ${systemName}
    done;
  '';

  meta = with lib; {
    description = "General purpose quantum chemistry program. Tools, not Toys!";
    homepage = "https://www.turbomole.org/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = [ maintainers.sheepforce ];
  };
}
