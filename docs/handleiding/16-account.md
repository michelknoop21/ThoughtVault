groep: Instellingen
samenvatting: Lees wanneer je wel en niet een ThoughtVault-account nodig hebt en wat je met een account kunt beheren.

# Account

ThoughtVault werkt standaard lokaal, en dan heb je geen account nodig. Opnemen, transcriberen en notulen maken gaan zonder inloggen. Een ThoughtVault-account is alleen nodig als je bij **Instellingen** > **Verwerking** voor **Cloud** kiest, zie [Instellingen](instellingen.html#verwerking-lokaal-of-cloud).

## Zonder account werken

::: macos windows
Op het tabblad **Account** van **Instellingen** staat in de lokale modus de tekst "Deze app werkt lokaal zonder ThoughtVault-login." Je gegevens voor de notulen, zoals je naam en functie, vul je in op het tabblad **Notulen**.
:::

::: ios
Onder **Instellingen** > **Account** staat bij de rij **Account** de tekst "Niet ingelogd" zolang je lokaal werkt. Dat is geen foutmelding: de app heeft dan geen account nodig.
:::

De naam en het e-mailadres die de app bij de eerste start vraagt, vormen geen account. Ze worden alleen gebruikt om je meldingen te beantwoorden. Aanpassen doe je bij de instellingen voor support, zie [Support en meldingen](support-en-meldingen.html).

## Inloggen voor de modus Cloud

::: macos
1. Kies bij **Instellingen** > **Verwerking** de locatie **Cloud**.
2. Open het tabblad **Account** en klik op de rij met "Niet ingelogd".
3. Vul je **E-mailadres** en **Wachtwoord** in.
4. Klik op **Inloggen**.

Heb je twee-factor verificatie aanstaan, dan vraagt de app daarna om de 6-cijferige code uit je authenticator-app. Met **Lokaal gebruiken (zonder server)** op het inlogscherm zet je de app terug op lokaal.
:::

::: windows
1. Kies bij **Instellingen** > **Verwerking** voor **Cloud**. Het inlogscherm opent zodra je naar een ander scherm gaat.
2. Vul je **E-mailadres** en **Wachtwoord** in.
3. Vink **Onthoud mij** aan als je je gegevens op deze pc wilt bewaren.
4. Klik op **Inloggen**.

Heb je twee-factor verificatie aanstaan, dan vraagt de app daarna om de 6-cijferige code uit je authenticator-app. Met **Lokaal gebruiken zonder account** ga je terug naar de lokale modus.
:::

::: ios
1. Kies bij **Instellingen** > **Verwerking** de verwerkingsmodus **Cloud**.
2. Tik onder **Account** op **Account** en daarna op de rij met "Niet ingelogd".
3. Vul je **E-mailadres** en **Wachtwoord** in.
4. Tik op **Inloggen**.
:::

### Wachtwoord vergeten

1. Kies op het inlogscherm **Wachtwoord vergeten?**.
2. Vul je e-mailadres in en laat een code versturen.
3. Vul de code uit de e-mail in.
4. Kies een nieuw wachtwoord en vul het twee keer in.

::: macos ios
Het nieuwe wachtwoord moet minimaal 8 tekens hebben. Komt de code niet aan, gebruik dan **Code opnieuw versturen**.
:::

## Je account beheren

Deze functies zie je alleen als je bent ingelogd.

::: macos ios
Open **Instellingen** > **Account** en kies de rij met je naam.
:::

::: windows
Klik op het startscherm rechtsboven op het poppetje. Ben je niet ingelogd, dan opent die knop de instellingen.
:::

| Onderdeel | Wat je er doet |
|-----------|----------------|
| **Profiel** | Je naam wijzigen. Je e-mailadres en je rol (**Admin** of **Gebruiker**) staan erbij. |
| **Wachtwoord wijzigen** | Je huidige wachtwoord invullen en twee keer het nieuwe. |
| Twee-factor authenticatie | **2FA activeren**, later **2FA deactiveren** of **Backup codes opnieuw genereren**. |
| **Sessie** | **Uitloggen**. |

### Twee-factor authenticatie aanzetten

1. Kies **2FA activeren**.
2. Scan de QR-code met je authenticator-app, of typ de getoonde code over.
3. Vul de 6-cijferige verificatiecode uit de app in en bevestig.
4. Bewaar de backup codes die daarna verschijnen op een veilige plek.

Elke backup code werkt één keer, voor als je niet bij je authenticator-app kunt. Uitzetten gaat met **2FA deactiveren**, waarbij je je wachtwoord invult ter bevestiging.

### Uitloggen

Kies **Uitloggen** en bevestig.

::: windows
Na het uitloggen staat de app weer in de lokale modus.
:::

::: macos ios
Op een apparaat met Touch ID of Face ID staat bij het account ook de schakelaar **Touch ID inloggen** of **Face ID inloggen**. Aanzetten lukt alleen terwijl je bent ingelogd.
:::

### Gegevens opvragen of je account verwijderen

::: macos ios
Onder **Privacy & Gegevens** staat **Gegevens exporteren (GDPR)**. Je account verwijderen gaat niet in de app zelf: onder **Gevarenzone** staat **Account verwijderen via support**, waarmee je een verzoek mailt naar support@prezent.nl. De app noemt daarbij een verwerkingstermijn van 30 dagen.
:::

::: windows
Onder **Privacy & gegevens** staat **Gegevens exporteren (AVG)**. Die export is op Windows nog niet beschikbaar: de knop meldt "Data export is nog niet beschikbaar". Je account laten verwijderen doe je per e-mail aan support@prezent.nl, het adres staat onder **Account verwijderen**.
:::

## Beheerders

::: macos
Heeft je account de rol Admin, dan staat er in de zijbalk een extra onderdeel **Admin** (`Cmd+7`) met de tabbladen **Overzicht**, **Gebruikers**, **Uitnodigingen**, **Feedback**, **Fouten** en **Instellingen**. Zonder die rol zie je het onderdeel niet.
:::

::: ios
Heeft je account de rol Admin, dan staat onder **Instellingen** > **Organisatie** de rij **Admin**.
:::

::: windows
De Windows-app heeft geen beheerscherm in de navigatie.
:::
