# Third-party notices

- **REFramework**, praydog and contributors, MIT: https://github.com/praydog/REFramework . Installer target: `v1.5.9.1`. License: `third_party/REFramework-LICENSE.txt`. Source is not vendored here. A release may include an unmodified, checksum-verified official RT archive; otherwise the installer obtains the appropriate official RT / NonRT archive.
- **OpenVR C# bindings**, Valve Corporation, SDK tag `v1.26.7`, BSD-style license: https://github.com/ValveSoftware/openvr . Vendored at `support/openvr_api.cs`; license at `support/OpenVR-LICENSE.txt`. Local change: add missing generated alias `using vrshared_double = System.Double;`. The helper uses the OpenVR client library supplied by the user's REFramework installation.
- **.NET Framework / Windows APIs** are system dependencies, not redistributed as framework runtimes here. Windows input uses `SendInput`; belt textures use `System.Drawing`.
- Resident Evil 2, character models, weapon assets and associated marks belong to Capcom and other respective owners. No Capcom game data, saves or extracted assets are licensed under this project's MIT license or included in the source tree.

This project is independent and is not endorsed by Capcom, Valve or Meta. Upstream documentation and issue reports informed troubleshooting; they do not certify this mod's compatibility.

## Физические гранаты

Native-интеграция 0.7.0 опирается на MIT-скрипт REFramework v1.5.9.1 `scripts/re2_vr_grenade.lua`: генерация, поворот скорости и Equipment.use. Полная лицензия upstream включена в third_party/REFramework-LICENSE.txt. Старый autorun заменён заглушкой для предотвращения параллельного броска.
