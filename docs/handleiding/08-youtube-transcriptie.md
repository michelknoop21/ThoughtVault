groep: Opnemen en verwerken
samenvatting: Je weet wanneer de knop YouTube-video beschikbaar is en laat van een YouTube-video een transcriptie en notulen maken.

# YouTube-transcriptie

ThoughtVault kan van een YouTube-video notulen maken zonder dat je de video afspeelt. De verwerking gebeurt op de ThoughtVault-server, niet op je eigen apparaat.

## Wanneer de functie beschikbaar is

De knop **YouTube-video** staat er alleen als aan beide voorwaarden is voldaan:

- De verwerking staat op **Cloud**. Bij lokale verwerking, de standaard, is de functie uit.
- De beheerder van de server heeft YouTube-transcriptie aangezet.

Zie je de knop niet, dan geldt een van de twee niet voor jou. Wat **Cloud** inhoudt, staat in [Lokaal of via de cloud verwerken](lokaal-of-cloud.html).

## Een video laten verwerken

::: macos
1. Open het scherm **Opnemen**.
2. Kies bij **Opnameprofiel** het profiel voor de notulen.
3. Klik bij **Snelle acties** op **YouTube-video**.
4. Klik op **Verbind Google Account** als die knop er staat, en log in bij Google.
5. Plak de link van de video in het veld **Plak een YouTube URL...**.
6. Klik op **Transcriberen**.

Is je Google-account gekoppeld, dan staat er **Google verbonden** met de knop **Ontkoppel**.
:::

::: ios
1. Open het scherm **Opnemen**.
2. Kies bij **Opnameprofiel** het profiel voor de notulen.
3. Tik op **YouTube-video**.
4. Tik op **Verbind Google Account** als die knop er staat, en log in bij Google.
5. Plak de link van de video in het veld **Plak een YouTube URL...**.
6. Tik op **Transcriberen**.
:::

::: windows
1. Open het scherm **Opnemen**.
2. Klik bij **Snelle acties** op **YouTube-video**.
3. Plak de link van de video in het veld **Video-URL**.
4. Kies bij **Template** het profiel voor de notulen.
5. Klik op **Verwerken**.

De link moet beginnen met `youtube.com/watch?v=`, `youtube.com/shorts/`, `youtube.com/live/` of `youtu.be/`. Bij een andere link meldt de app **Ongeldige YouTube URL**.
:::

De video verschijnt als taak op het scherm [Taken](taken.html). De notulen staan na afloop bij **Notulen**.

::: macos ios
Heeft de video geen ondertiteling, dan meldt de app: **Geen ondertiteling beschikbaar. Video wordt gedownload en getranscribeerd via Whisper (dit kan enkele minuten duren).** De server downloadt dan het geluid en zet het zelf om naar tekst.
:::
