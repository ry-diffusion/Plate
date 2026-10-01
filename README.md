# Newtray

App de menu bar para macOS que mostra o sinal, o tipo de rede celular (5G, LTE, 4G…) e a bateria do iPhone com Instant Hotspot direto na status bar, sem precisar abrir o menu de Wi-Fi.

```
▂▄▆█ 5G          (no hotspot)
▂▄▆█             (em outro Wi-Fi)
▂▄▆█ 5G
····             (com a bateria do iPhone ligada: um ponto sob cada barra)
```

## Recursos

- **Torre de sinal** (0–4 barras) e **tipo de rede** do iPhone, atualizados conforme o iPhone anuncia mudanças.
- **Bateria do iPhone** (opcional, desligada por padrão) como 4 pontos em fileira embaixo da torre (um sob cada barra), acesos da esquerda pra direita. Vale tanto no modo automático quanto no manual. Sem porcentagem: o iPhone só anuncia a bateria em quartos (0, 25, 50, 75, 100).
- **Modo automático** (padrão): torre sempre; o texto da rede (5G/LTE) só aparece quando o Mac está usando o hotspot do iPhone.
- **Modo manual**: escolher em *Mostrar na barra* quais itens aparecem (barras, tipo de rede).
- Menu com um cabeçalho por iPhone: ícone real do modelo, nome, modelo comercial (`iPhone18,1` → *iPhone 17 Pro*), rede e bateria em pontos. Também tem horário da última atualização, **Atualizar** (⌘R) e **Sair** (⌘Q).
- Sem ícone no Dock (`LSUIElement`).

## Requisitos

- macOS 27 ou mais recente.
- iPhone com Personal Hotspot, na mesma conta do iCloud, com Bluetooth e Wi-Fi ligados no Mac.

## Como funciona

| Dado | Fonte |
|---|---|
| Tipo de rede, barras, bateria, nome e identificador do modelo | `SFRemoteHotspotSession` (Sharing.framework, **API privada**) — a mesma fonte do menu de Wi-Fi do macOS |
| Nome comercial e ícone do modelo | `UTType` com a tag class `com.apple.device-model-code` (UTIs do CoreTypes do macOS) |
| Se o Mac está no hotspot | `NWPathMonitor.isExpensive` (Network, API pública, sem permissão de Localização) |
| Status bar | `NSStatusItem` com símbolo SF `cellularbars` em 15pt, alinhado aos ícones do sistema |

Valores de `networkType` recebidos do iPhone:

| Valor | Rede |
|---|---|
| 0 | — |
| 1 | 1x |
| 2 | GPRS |
| 3 | EDGE |
| 4 | 3G |
| 5 | H |
| 6 | 4G |
| 7 | LTE |
| 8 | 5G |

### Limitações

- **API privada**: não pode ir para a Mac App Store e pode quebrar em atualizações do macOS.
- **5G SA × NSA**: o iPhone só anuncia "5G", sem distinguir SA de NSA, então não dá para mostrar "5G+".
- A atualização depende do anúncio BLE do iPhone; o app reinicia a busca a cada 30s para forçar dados novos.

## Estrutura

```
Newtray/
├── NewtrayApp.swift            # App + AppDelegate (sem janelas)
├── StatusItemController.swift  # NSStatusItem, menu e opções de exibição
├── DeviceHeaderView.swift      # Cabeçalho do menu (SwiftUI)
├── HotspotDevice+Model.swift   # Nome comercial, ícone e torre com os pontos da bateria
├── AppIcon.icon                # Ícone (Icon Composer, com variações escuro/transparente/tingido)
└── HotspotMonitor.swift        # SFRemoteHotspotSession + NWPathMonitor
```

## Build

Abrir `Newtray.xcodeproj` no Xcode e rodar o scheme **Newtray**, ou:

```bash
xcodebuild -project Newtray.xcodeproj -scheme Newtray -configuration Release build
```
