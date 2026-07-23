# Design QA — Repertório em duas colunas

## Resultado

**Aprovado nos estados inspecionados.** O modo Repertório agora mantém somente repertórios e ordem como colunas permanentes. A biblioteca aparece como uma bandeja direita opaca de 420 px, separada por divisor nativo e sem sombra ornamental.

## Cobertura visual e funcional

- Estado normal confirmado em duas colunas, com a ordem como superfície principal.
- `Adicionar músicas` abre a bandeja, move o foco para a busca e deixa explícito `Adicionar a: Showboat Jul 23`.
- A bandeja apresenta `Todas as músicas` e os três repertórios atuais no dropdown `Mostrar`.
- O filtro `Showboat Jul 23` retornou 26 músicas únicas; busca combinada com o dropdown reduziu o resultado imediatamente.
- Contadores `1x` e ações de adicionar outra ocorrência permanecem visíveis.
- O fundo opaco evita sobreposição visual com o cabeçalho e a ordem; o divisor é suficiente para delimitar a superfície.
- `Esc` fecha a bandeja. Os botões de cabeçalho e o `X` expõem nomes e hints acessíveis.
- Estados desconectado, somente leitura e configurado continuam distinguíveis por texto e cor.
- Reduzir Movimento remove a animação da bandeja pelo ambiente de acessibilidade.
- A janela mantém o mínimo declarado de 920 × 640; a inspeção visual foi executada no app empacotado em 1340 × 768.

## Observações

- O fluxo editor → cancelar/salvar → biblioteca é preservado no estado compartilhado, incluindo busca e dropdown. A última tentativa de captura desse retorno encerrou o pipe de inspeção do Computer Use, sem encerrar o app; o comportamento está coberto pela implementação e pelo harness.
- Nenhum problema crítico, médio ou baixo permaneceu nos estados visuais capturados.

## Verificações técnicas

- Testes Swift: 5/5.
- Harness: 214/214.
- Build de produção: concluído.
- Assinatura ad-hoc: verificada com `codesign --verify --deep --strict`.

## Reconexão do PA700

- O indicador circular permanece discreto no repouso e expõe `Reconectar PA700` como ação acessível.
- Hover revela o símbolo de recarregar; durante a verificação, o indicador usa progresso nativo.
- Sem resposta, o estado muda para vermelho com `PA700 sem resposta` e orientação curta.
- O reset recria cliente e portas CoreMIDI sem emitir Panic ou Stop.
- `Aplicar no PA700` permanece bloqueado até uma resposta de identidade atual confirmar a conexão.
