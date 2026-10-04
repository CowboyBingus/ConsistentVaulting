Supports Helldivers 2 Steam build 25480438 / EXE 1.8.46015.0.

Offline source, package and read-only module checks passed. Vaulting, slope and
ledge assists were confirmed in live play on this build, and recorded play
measured about 0.25 ms of main-thread time per mission frame for v8.8 (about
0.44 ms before). In live play on 2026-10-04, v8.9 measured 0.026 ms per frame
in client missions and 0.011 on the ship. The 21 external live checks did not write game memory or
installed files.

Public source excludes raw memory captures and private session recordings.
Install with the game closed, then Purge / Deploy in one mod manager.
Use Bingus Shared Loader v18 or newer (v19 is current).
