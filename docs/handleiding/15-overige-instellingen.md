groep: Instellingen
samenvatting: Vul je woordenlijst, kies je standaardprofiel, koppel je agenda en Obsidian en regel updates en toegang tot de microfoon.

# Overige instellingen

Naast de keuzes voor transcriptie en notulen uit [Instellingen](instellingen.html) heeft het scherm **Instellingen** onderdelen voor je woordenlijst, je standaardprofiel, je agenda, Obsidian, updates en permissies. Op Mac en Windows zijn dat tabbladen, op iPhone en iPad rijen die een eigen pagina openen.

## Woordenlijst

Namen en vaktermen die steeds verkeerd worden herkend, zet je in de woordenlijst. De app vervangt de verkeerde spelling dan in volgende notulen. De lijst blijft op je apparaat.

::: macos
Open het tabblad **Woordenlijst**.
:::

::: windows
Scrol op het tabblad **Verwerking** naar **Woorden en namen**.
:::

::: ios
Tik onder **Notulen generatie** op **Woordenlijst**.
:::

Met **Term toevoegen** leg je de juiste spelling vast, met de verkeerde spellingen erbij. Alle stappen, het corrigeren vanuit een notule en de voorstellen na een gesprek staan in [Woordenlijst](woordenlijst.html).

## Notulen: standaardprofiel en gegevens over jou

::: macos
Op het tabblad **Notulen** kies je bij **Standaard profiel** het profiel dat bij een nieuwe opname al is geselecteerd, of **Geen standaard**. Onder **Profiel** vul je in wie je bent: **Naam**, **Rol / Functie**, **Organisatie** en bij **Hoe noemen collega's jou?** de namen waarmee je wordt aangesproken. Daarmee kan de app actiepunten aan jou koppelen. Klik op **Profiel opslaan**.

Met **Onboarding opnieuw doorlopen** start je de welkomststappen en toestemmingen opnieuw.
:::

::: windows
Op het tabblad **Notulen** kies je bij **Standaard notulentemplate** het profiel voor nieuwe opnames. Onder **Profielen beheren** pas je profielen aan. Onder **Profiel** vul je in wie je bent: **Naam**, **Rol / Functie**, **Organisatie**, **Hoe noemen collega's jou?**, **Typische vergadertypen** en **Expertise / onderwerpen**. Daarmee kan de app actiepunten aan jou koppelen. Klik op **Profiel opslaan**.

Met **Onboarding opnieuw doorlopen** start je de welkomststappen opnieuw.
:::

::: ios
Onder **Opname** > **Opnameprofielen** kies je het standaardprofiel. Onder **Notulen generatie** > **Over jou** vul je in wie je bent.
:::

Meer over profielen lees je in [Profielen](profielen.html).

## Agenda

::: macos ios
Standaard gebruikt de app Apple Agenda. Staat er "Geen toegang, vergaderingen worden niet gedetecteerd", kies dan **Agenda koppelen** en geef toestemming. De keuze **Agendabron** met **Microsoft 365** verschijnt alleen als die koppeling voor jouw omgeving is ingericht. Je verbindt dan met **Verbinden met Microsoft 365** en stopt met **Verbinding verbreken**. Onder **Aankomende vergaderingen** zie je wat de app in je agenda heeft gevonden.
:::

::: macos
Met de schakelaar **Automatische vergaderdetectie** krijg je een melding om de opname te starten zodra er een videogesprek begint.
:::

::: windows
Het tabblad **Agenda** koppelt alleen met Microsoft 365. Klik op **Verbinden met Microsoft 365** en log in. Na het koppelen staat er "Verbonden:" met je e-mailadres en kun je stoppen met **Verbinding verbreken**. Zie je "Agenda-koppeling niet geconfigureerd. Neem contact op met de beheerder.", dan is de koppeling voor jouw omgeving niet ingericht en kun je hem niet zelf aanzetten.
:::

## Obsidian

Met de schakelaar **Automatisch exporteren naar Obsidian** schrijft de app elke nieuwe notule naar je Obsidian-vault.

::: macos ios
1. Zet de schakelaar aan.
2. Kies bij **Vault-map** de knop **Kies map…** en selecteer de map van je vault.
3. Pas bij **Context-note** de naam aan als je een andere notitie met namen en termen wilt laten lezen.

De notulen komen als Markdown-bestand in die map te staan.
:::

::: macos
De velden **Base-URL**, **Vault-pad** en **API-sleutel** horen bij de plugin Local REST API van Obsidian. De app gebruikt ze alleen als je geen vault-map hebt gekozen. Met **Test verbinding** controleer je of de plugin bereikbaar is.
:::

::: windows
Op Windows loopt de koppeling via de plugin Local REST API van Obsidian.

1. Zet de schakelaar aan.
2. Vul bij **Base-URL** het adres van de plugin in. De standaard is `https://127.0.0.1:27124`.
3. Vul bij **Vault-pad** de map in je vault in. De standaard is `Notulen`.
4. Plak de sleutel uit de plugin bij **API-sleutel** en klik op **Opslaan**.
5. Klik op **Test verbinding**.
:::

## Algemeen en Geavanceerd

::: macos
Op **Algemeen** staat onder **Over** de versie van de app. In versies die zelf naar updates zoeken staat hier ook de schakelaar **Controleer op updates**. Staat die aan, dan toont de app een melding als er een nieuwe versie is.

Op **Geavanceerd** zie je onder **Permissies** de status van **Microfoon**, **Spraakherkenning** en **Systeemaudio**. Met **Systeeminstellingen openen** ga je naar de privacy-instellingen van macOS.
:::

::: windows
Op **Algemeen** staat de schakelaar **Automatisch bijwerken**. Nieuwe versies worden dan op de achtergrond gedownload en geïnstalleerd als je ThoughtVault afsluit, nooit tijdens een opname of verwerking. Met **Zoek naar updates** controleer je direct. Bij **Beweging van de geluidsgolf** kies je tussen **Windows volgen**, **Beweging aan** en **Rustige weergave**. Onder **Over** staat het versienummer.

Op **Geavanceerd** opent **Systeeminstellingen openen** de microfooninstellingen van Windows. Werk je in de modus Cloud, dan staat op dit tabblad de serververbinding in plaats van de permissies.
:::

::: ios
Onder **Account** > **Rechten** zie je de status van **Microfoon** en **Spraakherkenning**. Onder **Over ThoughtVault** staan de versie, de schakelaar **Controleer op updates** en **Onboarding opnieuw doorlopen**.
:::
