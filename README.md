# Armario

App personal para gestionar tu ropa: fotos de cada prenda, filtros, estado
(disponible / sucia / prestada / en reparación), "qué puedo ponerme hoy",
conjuntos, historial de uso y sugerencia según el tiempo.

- **Funciona sin internet.** Todo se guarda en el dispositivo.
- **Sincroniza entre tus dispositivos** con Supabase (opcional, plan gratuito).
- **Todo es gratis:** Flutter, GitHub Actions (repo público), GitHub Pages,
  Supabase Free y Open-Meteo. Nada pide tarjeta.

Un solo código (Flutter) para Android, Windows, iPhone y web.

---

## 1. Conseguir la app ya compilada (lo más fácil)

No hace falta instalar nada en tu PC. Cada vez que se sube código a la rama
`main`, GitHub compila todo solo.

1. Entra en el repo en GitHub → pestaña **Actions** → comprueba que la última
   ejecución de **Compilar** está en verde.
2. Ve a la pestaña **Releases** (columna derecha de la página principal del
   repo) → versión **latest**. Ahí están:
   - `armario.apk` → Android
   - `armario-windows.zip` → Windows
   - `armario-sin-firmar.ipa` → iPhone

### Android

1. Abre la página de Releases desde el navegador del móvil y descarga
   `armario.apk`.
2. Ábrelo. Android te pedirá permitir "instalar apps desconocidas" para el
   navegador: acepta e instala.

**Importante – firma estable (hazlo una vez):** para que las actualizaciones
se instalen encima sin perder datos, el APK debe firmarse siempre con la misma
clave. Esa clave es un secreto y por eso no está en el repo:

1. En GitHub: repo → **Settings** → **Secrets and variables** → **Actions** →
   **New repository secret**.
2. Nombre: `ANDROID_KEYSTORE_BASE64`. Valor: el texto de tu clave en base64.
3. Guarda también ese texto en un sitio seguro (gestor de contraseñas). Si lo
   pierdes, habrá que desinstalar y reinstalar la app (tus datos vuelven con
   la sincronización o con una copia de seguridad).

Si necesitas crear una clave nueva (requiere Java, que viene con Android
Studio):

```bash
keytool -genkeypair -keystore armario.jks -alias armario -keyalg RSA -keysize 2048 -validity 20000 -storepass armario -keypass armario -dname "CN=Armario"
```

y para pasarla a base64 en PowerShell:

```bash
[Convert]::ToBase64String([IO.File]::ReadAllBytes("armario.jks")) | Set-Clipboard
```

Sin ese secreto la app se compila igual, pero cada compilación lleva una firma
distinta y Android no dejará actualizar: tendrás que desinstalar primero.

### Windows

1. Descarga `armario-windows.zip` y descomprímelo en una carpeta que no vayas
   a borrar (por ejemplo `Documentos\Armario`).
2. Ejecuta `armario.exe`. La primera vez Windows puede mostrar "Windows
   protegió su PC": pulsa **Más información** → **Ejecutar de todas formas**
   (ocurre porque la app no está firmada con un certificado de pago).
3. Para actualizar, descomprime la versión nueva encima. Tus datos no están
   en esa carpeta (se guardan en tu carpeta de Documentos, archivo
   `armario.sqlite`), así que no se pierden.

### iPhone – opción A: .ipa con Sideloadly (app nativa)

Necesitas un PC con Windows, un cable y tu Apple ID gratuito.

1. Instala **iTunes** e **iCloud** descargados de la web de Apple (no las
   versiones de Microsoft Store) y **Sideloadly** (sideloadly.io, gratis).
2. Conecta el iPhone por cable y pulsa "Confiar" en el móvil.
3. Abre Sideloadly, arrastra `armario-sin-firmar.ipa`, escribe tu Apple ID y
   pulsa **Start**.
4. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos** →
   confía en tu Apple ID. En iOS 16 o posterior activa también
   **Ajustes → Privacidad y seguridad → Modo de desarrollador**.
5. **Caduca a los 7 días** (limitación de Apple con cuentas gratuitas).
   Vuelve a instalarla con Sideloadly *sin borrar la app*: los datos se
   conservan. Sideloadly puede renovarla automáticamente por wifi si el PC
   está encendido.

Con **SideStore** el proceso es parecido, pero una vez instalado SideStore
puede renovar la app desde el propio iPhone; sigue su guía oficial e instala
el `.ipa` desde su pestaña "My Apps".

Con un Apple ID gratuito solo puedes tener 3 apps instaladas así a la vez.

### iPhone – opción B: PWA (plan B, sin caducidad)

1. Activa GitHub Pages una vez: repo → **Settings** → **Pages** → en
   **Source** elige **GitHub Actions**. Luego relanza el workflow (Actions →
   Compilar → **Run workflow**).
2. En el iPhone abre con **Safari**: `https://TU-USUARIO.github.io/Armario/`
3. Botón **Compartir** → **Añadir a pantalla de inicio**.

Se abre a pantalla completa y funciona sin internet tras la primera carga.
Añádela a la pantalla de inicio: Safari puede borrar los datos de webs que no
se visitan en una semana si no están instaladas. Activa la sincronización o
haz copias de seguridad de vez en cuando.

La dirección es pública, pero no contiene ningún dato tuyo: los datos viven
en cada dispositivo y en tu Supabase, protegido con tu contraseña.

---

## 2. Sincronización: crear el proyecto de Supabase (gratis)

Es opcional: sin esto la app funciona igual, pero solo en cada dispositivo.

1. Entra en **supabase.com** → **Start your project** → regístrate (puedes
   usar tu cuenta de GitHub). No pide tarjeta.
2. **New project**: ponle nombre (`armario`), inventa una contraseña de base
   de datos (guárdala) y elige una región cercana (Europa). Plan **Free**.
3. Menú **SQL Editor** → **New query** → copia y pega todo el contenido de
   [`supabase/schema.sql`](supabase/schema.sql) → **Run**. Debe decir
   "Success". Esto crea las tablas, la seguridad (Row Level Security) y el
   almacén privado de fotos.
4. Crea tu usuario: **Authentication** → **Users** → **Add user** →
   **Create new user**: tu email, una contraseña y marca **Auto Confirm User**.
5. Cierra el registro para que nadie más pueda crear cuentas:
   **Authentication** → **Sign In / Providers** → desactiva
   **Allow new users to sign up**.
6. Copia los dos datos de conexión: **Project Settings** → **API** (o el
   botón **Connect**): la **Project URL** y la clave pública
   (**anon** o **publishable**).
7. En la app: **Ajustes → Servidor (Supabase)** → pega la URL y la clave →
   Guardar → inicia sesión con tu email y contraseña. Repite en cada
   dispositivo.

> Nunca uses ni pegues en ningún sitio la clave **service_role** / **secret**:
> esa se salta toda la seguridad. La app solo necesita la clave pública.

Los nombres de los menús de Supabase cambian de vez en cuando; si alguno no
coincide, busca el equivalente.

### Límites del plan gratuito

- **500 MB** de base de datos y **1 GB** de archivos. Cada prenda ocupa unos
  200–270 KB en fotos, así que caben varios miles.
- **El proyecto se pausa tras una semana sin uso.** La app no se rompe:
  sigue funcionando en local y en Ajustes verás "Sin conexión con el
  servidor". Para reactivarlo entra en supabase.com, abre el proyecto y pulsa
  **Restore**; al rato la app sincroniza sola lo pendiente. No dejes el
  proyecto pausado durante meses: Supabase avisa en su panel del plazo máximo
  para restaurarlo.
- Usar la app al menos una vez por semana con internet evita la pausa.

### Copia de seguridad

**Ajustes → Exportar copia completa** genera un `.zip` con `data.json` y
todas las fotos en JPEG. **Importar copia** lo fusiona con lo que haya (no
borra nada). Sirve para cambiar de móvil sin Supabase o para dejar de usarlo
algún día.

---

## 3. Compilar tú mismo en Windows (opcional)

Solo si quieres modificar el código o no depender de GitHub.

### Instalar herramientas (todas gratuitas)

1. **Git**: git-scm.com → instalador con las opciones por defecto.
2. **Flutter**: docs.flutter.dev → *Get started* → Windows. Descomprime el SDK
   en `C:\dev\flutter` y añade `C:\dev\flutter\bin` a la variable de entorno
   PATH.
3. **Visual Studio 2022 Community** (no VS Code) con la carga de trabajo
   **"Desarrollo para el escritorio con C++"**: necesario para la app de
   Windows.
4. **Android Studio**: al abrirlo por primera vez instala el Android SDK.
   Después ejecuta en PowerShell `flutter doctor --android-licenses` y acepta.

Comprueba que todo está bien (te dice qué falta):

```bash
flutter doctor
```

### Descargar el código

```bash
git clone https://github.com/TU-USUARIO/Armario.git
```

```bash
cd Armario
```

```bash
flutter pub get
```

### Probar en el PC

```bash
flutter run -d windows
```

### Generar la app de Windows

```bash
flutter build windows --release
```

El resultado queda en `build\windows\x64\runner\Release\` (hay que copiar la
carpeta entera, no solo el `.exe`).

### Generar el APK

```bash
flutter build apk --release
```

El resultado es `build\app\outputs\flutter-apk\app-release.apk`. Para que
lleve tu firma estable, copia tu `armario.jks` a `android\app\` (Git lo
ignora, no se subirá).

### Versión web

```bash
flutter build web --release --no-web-resources-cdn
```

### Claves en la compilación (opcional)

Para que la app venga ya configurada con tu Supabase, copia
`config.example.json` a `config.json` (ignorado por Git), rellénalo y añade a
cualquier comando de compilación:

```bash
flutter build apk --release --dart-define-from-file=config.json
```

En GitHub Actions se consigue lo mismo creando los secretos `SUPABASE_URL` y
`SUPABASE_ANON_KEY`.

### Tests

```bash
flutter test
```

---

## Estado del proyecto

Ver [PROGRESS.md](PROGRESS.md): qué está hecho, qué falta, decisiones y
próximo paso.
