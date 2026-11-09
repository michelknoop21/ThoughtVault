# Bestaande transcriptieproef inhoudelijk beoordeeld

Bron: centrale job `b87ad05bc9ec493da1b60a96bd531328`, synthetische
Waddenspoor-clip van 29,886 seconden. Gedownloade resultaten zijn tegen het
centrale artifactmanifest gehasht. Geen nieuwe inferentie, modeldownload of
appinstelling gewijzigd. Dit is geen menselijke luister- of microfoonacceptatie.

| Bestaande configuratie | Tijd clip | Inhoud bij de tweede actie |
|---|---:|---|
| Faster Whisper Small int8 | 9,01 s | `Hier is controleerde inhoud` in plaats van Iris als actiehouder |
| Whisper Small | 69,97 s | Dezelfde verloren actiehouder |
| Whisper Large v3 | 400,59 s | Iris en Ruben herkenbaar; bedragen, deadlines en voorwaarden behouden |

De twee Small-routes zijn voor deze naam-/actieproef niet geaccepteerd, ook al
zijn Faster Whisper's snelheid en geheugengebruik gunstig. Het Large-resultaat
is op deze korte bron inhoudelijk beter, maar de gemeten CPU-doorlooptijd voldoet
niet aan het geplande pilotcriterium voor verwerking binnen de opnameduur.
Geen lineaire voorspelling telt hier als uitgevoerde uurproef.

Het eerder bewaarde native Parakeet-resultaat bij
`8667a70b30584695942917a48fde7c7e` bevat de leesbare Iris- en Ruben-acties.
Die bestaande kandidaat moet daarom bij de volledige appproef worden vergeleken,
met fysieke audio en de echte lange bron voordat een standaard wordt gekozen.
De eerste proefroute uit het plan wordt alleen behouden als inhoud én snelheid
bewezen zijn. Bestaande gebruikersvoorkeuren blijven behouden.
