idt3map
=======

Fork of `NetRadiant-custom <https://github.com/Garux/netradiant-custom>`_
which builds only its ``q3map2`` map compiler, with a standalone CMake build
for Linux, macOS and Windows (MinGW-w64 GCC).

Layout
------

The tree is kept as close to upstream as possible, so that changes from
upstream merge without conflicts:

- ``tools/quake3/`` holds q3map2 itself, ``regression_tests/`` its
  regression maps
- ``include/`` and ``libs/`` only contain the files q3map2 needs
- ``.legacy/`` holds everything else from upstream (the editor, plugins,
  other compilers, setup data, docs, upstream's own README and workflows),
  moved there unchanged with its relative paths
- ``CMakeLists.txt`` builds q3map2 (see below)

This README is named ``README.rst`` rather than ``README.md``, so that
upstream's ``README.md`` could move to ``.legacy/`` as a clean rename.

Building
--------

With CMake and Ninja, using the dependencies (zlib, libpng, libjpeg,
libxml2, glib, assimp) installed on the system:

.. code-block:: sh

   cmake -S . -B build -G Ninja
   cmake --build build

Options:

- ``-DQ3MAP2_VENDORED_ASSIMP=ON`` builds the assimp fork vendored in
  ``libs/assimp`` and links it statically instead of using the system
  assimp. This is the default on Windows, as MSVC built assimp packages
  are not ABI compatible with MinGW GCC.
- ``-DQ3MAP2_VERSION_SUFFIX=<suffix>`` appends ``-<suffix>`` to the
  version string q3map2 reports

MSVC is not supported, because the sources depend on GCC/Clang.

``CMakeLists.txt`` does not duplicate upstream's source lists, but reads
them from upstream's ``Makefile`` at configure time, along with the version
numbers. That's why the ``Makefile`` stays in place, although it is not
used for building anymore.

The build is reproducible: source paths embedded via ``__FILE__`` are made
relative (``-ffile-prefix-map``) and Windows executables contain no link
timestamp. Set ``SOURCE_DATE_EPOCH`` to also fix ``__DATE__`` /
``__TIME__``.

Merging from upstream
---------------------

.. code-block:: sh

   git fetch https://github.com/Garux/netradiant-custom.git master
   git -c merge.directoryRenames=true merge FETCH_HEAD

- Files below ``.legacy/`` were moved there unchanged, so git detects them
  as renames and applies upstream changes to them in their new place
- ``merge.directoryRenames=true`` makes git put files upstream adds to a
  directory which was moved as a whole (e.g. ``radiant/``) below
  ``.legacy/`` as well, instead of stopping with a conflict asking for
  confirmation
- New files upstream adds to ``include/`` or ``libs/`` stay where they
  are. If they aren't needed by q3map2, move them to ``.legacy/`` with
  ``git mv``
- If q3map2 starts to use a header from ``.legacy/``, the build fails;
  move it back with ``git mv .legacy/<path> <path>``
- The root ``.gitignore`` and ``.gitattributes`` are merged as the union
  of both sides (``merge=union``), so the lines added by this fork don't
  conflict with upstream changes
