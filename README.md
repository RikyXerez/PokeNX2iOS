# PokeNX2iOS

App de macOS que genera la IPA de **Pokémon: Let's Go, Pikachu!** para iPhone y iPad con todas las mejoras del proyecto NXnative. No lleva ningún archivo del juego: cada persona importa los suyos, sacados de su consola.

## Basado en NXnative

PokeNX2iOS se basa en **[NXnative](https://github.com/seedds/nxnative)** (licencia MIT), el proyecto que ejecuta juegos de Nintendo Switch de forma nativa en iPhone, iPad y Mac. No es un emulador: el código del propio juego corre en el chip de Apple y los gráficos de Switch se reconstruyen sobre Metal.

Esta herramienta no sustituye a NXnative, sino que lo usa como motor. Empaqueta una copia del código de NXnative con nuestros cambios para Let's Go, añade el perfil del juego y los mods, y ejecuta su script `build_ipa_from_nsp.py` desde una interfaz gráfica. Los créditos de NXnative y de los proyectos en los que se apoya (d2r-mobile, Ryujinx, Atmosphère, LibHac, SPIRV-Cross y otros) están en su [README](https://github.com/seedds/nxnative#acknowledgements).

PokeNX2iOS no tiene relación con Nintendo, The Pokémon Company ni Game Freak.

## Qué pide

1. El **juego base** en NSP (`010003F003A34000`, v0).
2. El **update 1.0.2** en NSP (`010003F003A34800`, v131072). Las mejoras están hechas para esta versión exacta, así que otra versión se rechaza.
3. Su **prod.keys**. Se lee en su sitio: no se copia y sus valores no se muestran nunca.

## Qué aplica

- **Motor NXnative de la rama `unificado2`** (nuestro fork sobre seedds/nxnative 6138a54). Incluye las correcciones de Let's Go: servicios de Poké Ball Plus, BLE y BCAT, mando en modo consola, fin de vídeo y heap de la intro, shaders GFLXPACK y YEBIS (los captura del propio juego al compilar), reloj de usuario y fechas de guardado, audio de vídeos, pantalla completa con la interfaz ajustada, pad virtual que se puede ocultar, pantallas más estrechas que 16:9 y la pestaña Pokémon de Ajustes de iOS.
- **Perfil del juego** `game.tsv` (memoria, NVN, `libc_wallclock`, `libc_localtime utc`, `touch_flick_a`, `ui_vs`, captura GLSLC). Las tablas de shaders se vuelven a generar a partir de los archivos de cada persona.
- **Mods**, que luego se activan o desactivan en Ajustes de iOS → Pokémon:
  - *Pantalla completa*, adaptado del mod 21:9 Ultrawide de Fl4sh_#9174. El aspecto se mide en cada pantalla.
  - *Combates salvajes* (Wild Battles, de GameBanana). Antes de desbloquear "Jugar con Pikachu" un combate salvaje se cuelga.
- **Idioma** español por defecto (se puede elegir otro) y bundle ID `com.pokenx2ios.pokemonletsgo` (se puede cambiar).

## Crear la app (una vez)

Hace falta un clon de NXnative con la rama `unificado2`, que contiene nuestros cambios para Let's Go. Esa rama está en local y todavía no se ha publicado. Con el clon de [seedds/nxnative](https://github.com/seedds/nxnative) sin esa rama, la app se crea igual, pero el motor no tendrá las mejoras.

En el Mac donde está el repositorio `nxnative`:

```
cd ~/Desktop/NXnative/PokeNX2iOS
scripts/make_app.sh                 # usa ../nxnative y la rama unificado2
open dist/PokeNX2iOS.app
```

`REFRESH_LETSGO="$HOME/Desktop/NXnative/Pokemon Lets GO" scripts/make_app.sh` vuelve a copiar antes el `game.tsv` y los mods actuales de esa carpeta.

La app solo lleva lo que está en commit en la rama. Si haces cambios nuevos en `nxnative`, haz commit y vuelve a ejecutar `make_app.sh`.

## Usarla

1. Importa los tres archivos, arrastrándolos o con **Elegir…**.
2. Elige la carpeta de trabajo. Hace falta el doble del tamaño de los NSP más 10 GB, unos 19 GB. La IPA se guarda ahí.
3. Revisa los requisitos: Apple silicon, Xcode 27.1 con Metal Toolchain, Homebrew, xcodegen, zstd, glslang, .NET SDK 10 y Python 3.12+. **Instalar** abre Terminal con el comando.
4. Pulsa **Generar IPA**. La primera vez tarda entre 30 y 60 minutos, y las siguientes unos minutos.
5. Instala la IPA con AltStore, Sideloadly o LiveContainer. Si tu herramienta lo permite, fírmala con **Increased Memory Limit**.

Dentro de la carpeta de trabajo, `PokeNX2iOS_work/` guarda el motor, un entorno de Python propio, los enlaces a los NSP con los mods (`input/`), la caché de compilación (`input/010003F003A34000_build/`) y los registros (`logs/`).

## Cómo funciona

Ejecuta `scripts/build_ipa_from_nsp.py` de NXnative con `--progress json` y muestra sus eventos (ver `nxnative/docs/frontends.md`):

```
build_ipa_from_nsp.py input -k prod.keys -p v131072 -l es --bundle-id … -o PokemonLetsGoPikachu.ipa \
    --profile-out input/010003F003A34000_build/profile --progress json
```
