# FragmentomicsBenchmark

Auditoria metodológica sobre o uso de modelos de fundação genômica e redes *Attention-MIL* na análise de fragmentos de DNA livre circulante (cfDNA) para detecção de câncer. O projeto avalia a contribuição isolada de cada decisão de engenharia por meio de validação cruzada independente (5 sementes $\times$ 5 partições = 25 repetições).

---

## 1. Figuras e Diagnóstico Visual

### Figura 1: Decomposição da Cadeia de Processamento

Esta figura decompõe um modelo de aprendizado profundo em etapas sucessivas para identificar qual decisão de projeto provocou a variação no desempenho diagnóstico. A métrica no eixo vertical (AUROC) mede a capacidade de distinguir pacientes com câncer de indivíduos saudáveis, onde 1,0 representa separação perfeita e 0,5 corresponde ao acaso.

* **Simples vs. Complexo (Painel A):** O ponto de partida (barra cinza) é o modelo mais elementar: calcula a média das características do DNA e aplica uma regressão logística clássica, alcançando AUROC de 0,830. O ponto final (barra preta) é o modelo profundo completo (*Attention-MIL* com codificador genômico), cujo desempenho cai para 0,725.
* **Cascata de Etapas:** Cada barra intermediária altera um único parâmetro, mantendo todos os outros fixos:
  * **COMPRIMENTO (+0,005):** A adição do tamanho molecular produz ganho marginal.
  * **NORMALIZAÇÃO (-0,059):** A padronização dos dados no nível de fragmento altera negativamente a escala em relação à padronização no nível do paciente.
  * **CABEÇA (+0,079):** A substituição da regressão logística por uma rede neural multicamada melhora a separação.
  * **PROJEÇÃO (+0,003):** A inserção de uma camada matemática após a média mantém o desempenho estável.
  * **ORDEM (-0,156):** O deslocamento dessa mesma camada com ativação não linear (ReLU) para antes do cálculo da média provoca a maior queda de desempenho observada.
  * **AGREGADOR (+0,024):** A substituição da média simples por pesos aprendidos de atenção recupera pouco sinal biológico.
* **Confirmação Estrutural (Painel B):** A repetição das etapas utilizando contagens elementares de tetranucleotídeos (4-mers) reproduz a queda na etapa ORDEM (-0,117), demonstrando que o efeito decorre da ordem matemática das operações e não do codificador genômico.

![Figura 1 - Onde o sinal se perde na cadeia de agregação](Figura_1_Escada.png)

**Síntese dos achados:** A perda de desempenho do modelo profundo decorre predominantemente da etapa ORDEM (-0,156 de AUROC). Ao aplicar funções não lineares sobre fragmentos ruidosos antes de agrupá-los por média, as variações negativas são eliminadas, impedindo o cancelamento do ruído estocástico.

---

### Figura 2: Generalização e Transferência entre Coortes

Este gráfico avalia o que ocorre com o desempenho diagnóstico quando os modelos treinados em um centro clínico são testados em uma população e uma patologia diferentes, sem qualquer reajuste de parâmetros.

* **Coorte Interna (Baltimore, $n=537$):** Amostra de desenvolvimento composta por indivíduos ocidentais, abrangendo oito tipos tumorais em comparação com controles saudáveis.
* **Coorte Externa (Hong Kong, $n=122$):** Amostra de avaliação composta por indivíduos asiáticos, avaliando uma patologia ausente no treinamento (carcinoma hepatocelular) em comparação com controles saudáveis.
* **Linha de Acaso (0,5):** Demarca a fronteira onde o classificador perde a capacidade discriminativa. Valores inferiores a 0,5 indicam inversão nas probabilidades atribuídas.
* **Comportamento das Representações:**
  * **DELFI (Verde):** A quantificação macroscópica em janelas de 5 megabases mantém o desempenho, elevando-se de 0,819 para 0,863 na versão com rede neural, e de 0,774 para 0,820 na versão linear.
  * **Caduceus (Azul):** Os modelos baseados no codificador genômico sofrem colapso para 0,498 (nível do acaso), enquanto as configurações com atenção descem para a faixa entre 0,367 e 0,375.
  * **4-mers (Vermelho):** Apresentam declínio comparável ao do modelo genômico, recuando de 0,71–0,84 para 0,41–0,58.
  * **Comprimento (Cinza):** A métrica baseada exclusivamente no tamanho molecular cai de 0,74–0,80 para 0,34–0,46 devido a diferenças técnicas de preparo laboratorial entre os centros.

![Figura 2 - Transferência entre coortes](Figura_2_Generalizacao.png)

**Síntese dos achados:** As representações baseadas em resolução de base única memorizaram a estrutura demográfica e técnica da coorte de origem. Ao mudarem de população, essas representações perderam o sinal diagnóstico. Em contrapartida, a medição macroscópica em megabases (DELFI) mostrou-se invariante e generalizou para o novo centro.

---

### Figura 3: Separação de Grupos Clínicos e Doenças Hepáticas Benignas

Na prática clínica, o teste diagnóstico deve diferenciar o câncer verdadeiro de condições inflamatórias crônicas comuns no mesmo órgão. Este gráfico analisa a probabilidade de câncer predita pelos dois principais modelos em quatro grupos da coorte de Hong Kong: indivíduos saudáveis, portadores de hepatite B crônica, portadores de cirrose e pacientes com carcinoma hepatocelular.

* **Formato dos Gráficos de Violino:** A largura reflete a densidade de pacientes em cada nível de probabilidade predita (escala de 0,0 a 1,0), com linhas tracejadas indicando os quartis.
* **Caduceus (Painel Esquerdo, AUROC 0,498):** O modelo genômico atribui probabilidades próximas a zero para quase todos os indivíduos, independentemente de serem saudáveis ou portadores de tumor. As distribuições sobrepõem-se na base do gráfico.
* **DELFI (Painel Direito, AUROC 0,863):** A cobertura macroscópica estabelece um gradiente biológico:
  * Controles saudáveis concentram-se na faixa basal (probabilidade mediana em torno de 0,25).
  * Hepatite B e cirrose situam-se em níveis intermediários, refletindo a inflamação e a morte celular no tecido sem confundi-las com malignidade.
  * Carcinoma hepatocelular concentra-se no topo da escala (probabilidades entre 0,80 e 1,00).

![Figura 3 - Grupos Clínicos](Figura_3_Grupos_Clinicos.png)

**Síntese dos achados:** O modelo genômico profundo não reconhece a patologia na nova coorte. A abordagem macroscópica DELFI preserva a resolução biológica, distinguindo alterações inflamatórias benignas da presença efetiva de neoplasia hepática.

---

### Figura 4: Mecanismo Matemático da Ordem de Agregação

Esta figura expõe o fundamento analítico que torna a etapa ORDEM determinante no regime de sinal fraco, comparando o comportamento dos dados antes e depois da agregação por média.

* **Painel A (Fragmento Único):** Apresenta a distribuição dos valores de uma dimensão em moléculas individuais. As curvas de controles saudáveis (laranja) e casos de câncer (azul) sobrepõem-se com distância estatística mínima ($d = 0,0043$), indicando predominância de ruído estocástico sobre o sinal biológico.
* **Painel B (Média de 5.000 Fragmentos):** A mesma dimensão calculada sobre a média dos fragmentos de cada paciente afasta as distribuições ($d = 0,040$). O cálculo da média anula as flutuações simétricas em torno de zero, permitindo que a assinatura biológica emerja.
* **Painel C (Posição da Função Não Linear):** O eixo horizontal representa o cálculo da média seguido da ReLU; o eixo vertical representa a aplicação da ReLU em cada molécula antes do cálculo da média. Como camadas lineares comutam algebricamente com a média, todo o desvio em relação à reta diagonal decorre exclusivamente da ReLU. Ao truncar os valores negativos a zero no nível da molécula isolada, a ReLU destrói a simetria do ruído antes que a média possa cancelá-lo.

![Figura 4 - Mecanismo de Agregação](Figura_4_Mecanismo.png)

**Síntese dos achados:** No regime de baixa razão sinal-ruído, a agregação linear de milhares de instâncias é o mecanismo que torna o sinal mensurável. Transformações não lineares aplicadas antes desse agrupamento alteram a distribuição dos dados e reduzem a capacidade preditiva da rede.

---

## 2. Tabelas e Dados Experimentais (`04_results/`)

### 2.1. `escada.csv` — Decomposição Incremental da Arquitetura

Esta tabela quantifica o impacto individual de cada alteração de projeto ao longo da transição entre a regressão logística linear e a arquitetura *Attention-MIL*, mantendo a identidade telescópica entre os extremos.

| Etapa | Intervenção Arquitetural | $\Delta$ por dobra | $\pm$ DP | Escore agrupado [IC 95%] | Sinal (negativos) | $\Delta$ (atingiram limiar) | $\Delta$ (falhas) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **COMPRIMENTO** | Inclusão do tamanho em pares de bases | +0,005 | 0,002 | +0,005 [+0,000, +0,009] | 1/25 | +0,005 | — |
| **NORMALIZAÇÃO** | Padronização por paciente $\rightarrow$ por fragmento | -0,059 | 0,007 | -0,065 [-0,097, -0,034] | 22/25 | -0,059 | — |
| **CABEÇA** | Classificador linear $\rightarrow$ rede neural multicamada | +0,079 | 0,007 | +0,081 [+0,055, +0,109] | 0/25 | +0,079 | — |
| **PROJEÇÃO** | Projeção linear com ReLU **depois** da média | +0,003 | 0,004 | +0,008 [+0,001, +0,014] | 10/25 | +0,003 | — |
| **ORDEM** | Projeção linear com ReLU **antes** da média | **-0,156** | 0,033 | **-0,129 [-0,164, -0,097]** | **25/25** | **-0,129** | -0,241 |
| **AGREGADOR** | Média aritmética $\rightarrow$ mecanismo Attention-MIL | +0,024 | 0,022 | -0,050 [-0,096, -0,003] | 10/25 | +0,018 | +0,043 |

**Análise:** A etapa ORDEM concentra a maior perda isolada (-0,156 de AUROC), com sinal negativo em todas as 25 repetições. A substituição da média pelo operador de atenção (AGREGADOR) apresenta ganho modesto por dobra (+0,024) e variação negativa na estimativa agrupada (-0,050).

---

### 2.2. `desempenho_interno.csv` — Avaliação no Conjunto de Desenvolvimento

Esta tabela reúne as métricas de validação cruzada dos 16 braços avaliados na coorte de Baltimore ($n=537$), incluindo o desempenho médio, a variação entre sementes e a concordância de ordenamento entre réplicas.

| Configuração Avaliada | AUROC média | DP sementes | AUROC ensemble | Ganho ensemble | Concordância entre réplicas |
| :--- | :---: | :---: | :---: | :---: | :---: |
| Caduceus + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | **0,857** | 0,009 | 0,865 | +0,008 | 0,925 |
| Caduceus + Comprimento (Média $\rightarrow$ MLP) | 0,854 | 0,008 | 0,857 | +0,003 | **0,959** |
| 4-mers + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | 0,844 | 0,004 | 0,851 | +0,008 | 0,838 |
| Caduceus + Comprimento (Média $\rightarrow$ Logística) | 0,834 | 0,007 | 0,842 | +0,008 | 0,937 |
| Caduceus (Média $\rightarrow$ Logística) | 0,830 | 0,008 | 0,837 | +0,008 | 0,935 |
| Cobertura DELFI 5 Mb (MLP) | 0,819 | 0,018 | 0,829 | +0,010 | 0,790 |
| Histograma de Comprimentos (Logística) | 0,802 | 0,011 | 0,808 | +0,006 | 0,935 |
| Caduceus + Comp. (Média $\rightarrow$ Log., escala fragmento) | 0,775 | 0,002 | 0,776 | +0,002 | 0,972 |
| Cobertura DELFI 5 Mb (Logística) | 0,774 | 0,016 | 0,796 | +0,022 | 0,816 |
| Somente Comprimento (Atenção MIL) | 0,736 | 0,002 | 0,735 | -0,000 | 0,615 |
| 4-mers + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 0,729 | 0,033 | 0,662 | -0,068 | 0,197 |
| 4-mers + Comprimento (Projeção $\rightarrow$ Média $\rightarrow$ MLP) | 0,726 | 0,034 | 0,770 | +0,044 | 0,244 |
| Caduceus + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 0,725 | 0,033 | 0,687 | -0,038 | 0,178 |
| Composição de 4-mers (Média $\rightarrow$ Logística) | 0,714 | 0,012 | 0,740 | +0,026 | 0,739 |
| Caduceus + Comprimento (Projeção $\rightarrow$ Média $\rightarrow$ MLP) | 0,701 | 0,029 | 0,736 | +0,035 | 0,195 |
| Caduceus — Resíduo após 4-mers (Logística) | 0,604 | 0,025 | 0,620 | +0,017 | 0,658 |

**Análise:** Os modelos que aplicam a média antes da não linearidade obtêm AUROC superior a 0,83 e concordância de postos elevada (>0,92). As arquiteturas que projetam fragmentos antes da agregação apresentam queda de desempenho e redução acentuada na concordância (0,178 a 0,244).

---

### 2.3. `desempenho_externo.csv` — Avaliação na Coorte Externa

Esta tabela reporta os resultados de generalização cega na coorte de Hong Kong ($n=122$), medindo a diferença de AUROC em relação ao conjunto de treinamento.

| Configuração Avaliada | AUROC Externa | DP sementes | IC 95% [inf, sup] | AUROC Interna | Variação ($\Delta$) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Cobertura DELFI 5 Mb (MLP)** | **0,863** | 0,011 | [0,792, 0,922] | 0,819 | **+0,043** |
| **Cobertura DELFI 5 Mb (Logística)** | **0,820** | 0,020 | [0,740, 0,887] | 0,774 | **+0,046** |
| Composição de 4-mers (Média $\rightarrow$ Logística) | 0,581 | 0,017 | [0,465, 0,693] | 0,714 | -0,133 |
| 4-mers + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | 0,552 | 0,016 | [0,453, 0,654] | 0,844 | -0,292 |
| Caduceus + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | 0,498 | 0,021 | [0,395, 0,601] | 0,857 | **-0,359** |
| Caduceus + Comprimento (Média $\rightarrow$ MLP) | 0,494 | 0,011 | [0,393, 0,594] | 0,854 | -0,360 |
| Caduceus (Média $\rightarrow$ Logística) | 0,475 | 0,009 | [0,372, 0,585] | 0,830 | -0,355 |
| Caduceus + Comprimento (Média $\rightarrow$ Logística) | 0,470 | 0,007 | [0,367, 0,576] | 0,834 | -0,364 |
| Histograma de Comprimentos (Logística) | 0,460 | 0,008 | [0,352, 0,566] | 0,802 | -0,342 |
| 4-mers + Comprimento (Projeção $\rightarrow$ Média $\rightarrow$ MLP) | 0,425 | 0,019 | [0,326, 0,518] | 0,726 | -0,301 |
| Caduceus + Comp. (Média $\rightarrow$ Log., escala fragmento) | 0,419 | 0,004 | [0,319, 0,517] | 0,775 | -0,356 |
| 4-mers + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 0,412 | 0,034 | [0,313, 0,509] | 0,729 | -0,317 |
| Caduceus — Resíduo (Logística) | 0,403 | 0,018 | [0,307, 0,510] | 0,604 | -0,200 |
| Caduceus + Comprimento (Projeção $\rightarrow$ Média $\rightarrow$ MLP) | 0,375 | 0,029 | [0,278, 0,469] | 0,701 | -0,326 |
| Caduceus + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 0,367 | 0,032 | [0,268, 0,463] | 0,725 | -0,358 |
| Somente Comprimento (Atenção MIL) | 0,337 | 0,002 | [0,241, 0,427] | 0,736 | -0,399 |

**Análise:** As representações baseadas em sequência fina sofrem colapso diagnóstico na transferência entre centros, recuando para valores iguais ou inferiores a 0,50. A quantificação macroscópica em 5 Mb (DELFI) é a única que preserva e amplia o poder preditivo (+0,043).

---

### 2.4. `replicacao_degraus.csv` — Verificação das Etapas Críticas com 4-mers

Esta tabela verifica se os efeitos observados nas etapas ORDEM e AGREGADOR são reproduzíveis substituindo os vetores do modelo *Caduceus* por frequências elementares de 4-mers.

| Etapa Analisada | Caduceus ($\Delta \pm$ DP) | 4-mers ($\Delta \pm$ DP) | IC 95% 4-mers | Negativos (4-mers) | Consistência de Sinal |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **ORDEM** | -0,156 $\pm$ 0,033 | -0,117 $\pm$ 0,033 | [-0,113, -0,049] | 24/25 | **Sim** |
| **AGREGADOR** | +0,024 $\pm$ 0,022 | +0,003 $\pm$ 0,064 | [-0,154, -0,065] | 13/25 | **Sim** |

**Análise:** A retificação não linear prévia produz perda estrutural (-0,117) em 24 de 25 partições sob contagens simples de bases, confirmando que o mecanismo decorre do arranjo matemático da agregação.

---

### 2.5. `artefato_de_coorte.csv` — Separação entre Controles Saudáveis

Esta tabela testa se as representações distinguem indivíduos controles saudáveis de Baltimore ($n=261$) contra Hong Kong ($n=32$), sem envolver amostras tumorais, utilizando os primeiros $k$ componentes principais da PCA.

| Representação de Entrada | Dimensões | $k=1$ | $k=2$ | $k=5$ | $k=10$ | $k$ para AUROC $\ge 0,95$ |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Cobertura DELFI 5 Mb** | 1.614 | 1,000 | 1,000 | 1,000 | 1,000 | **1** |
| **Ocupação de Promotores** | 39.614 | 0,543 | 0,558 | 0,614 | 0,624 | **>25** |
| **Composição de 4-mers** | 256 | 0,780 | 1,000 | 1,000 | 1,000 | **2** |
| **Embedding do Caduceus** | 256 | 0,824 | 0,990 | 0,999 | 1,000 | **2** |

**Análise:** As representações por sequência (*Caduceus* e 4-mers) separam controles saudáveis dos dois centros com AUROC de 0,990 usando duas direções principais, confirmando a retenção de vieses técnicos e populacionais.

---

### 2.6. `diagnostico_atencao.csv` — Dispersão dos Pesos de Atenção

Esta tabela analisa a distribuição de importância calculada pelo mecanismo de atenção sobre os 5.000 fragmentos de cada paciente na coorte externa.

| Configuração com Atenção | $N_{\text{efetivo}}$ | Proporção da Bolsa | Correlação com Comprimento |
| :--- | :---: | :---: | :---: |
| Caduceus + Comprimento (Projeção $\rightarrow$ Atenção MIL) | **4.781,9** | **95,6%** | 0,146 |
| 4-mers + Comprimento (Projeção $\rightarrow$ Atenção MIL) | **4.802,7** | **96,1%** | 0,060 |
| Somente Comprimento (Atenção MIL) | 4.224,5 | 84,5% | 0,810 |

**Análise:** O número efetivo de instâncias supera 95% da capacidade total da bolsa (4.781 de 5.000 fragmentos), evidenciando que a atenção não localiza frações tumorais minoritárias no regime de sinal fraco.

---

### 2.7. `ponto_de_operacao.csv` — Sensibilidade Clínica com Especificidade Fixada

Esta tabela calcula a sensibilidade diagnóstica na coorte externa fixando o limiar de decisão para assegurar 95% de especificidade na coorte de treinamento.

| Configuração Avaliada | Especificidade Externa | Sensibilidade Externa |
| :--- | :---: | :---: |
| **Cobertura DELFI 5 Mb (MLP)** | **1,000** | **61,1%** |
| **Cobertura DELFI 5 Mb (Logística)** | 1,000 | 35,6% |
| Histograma de Comprimentos (Logística) | 0,969 | 10,0% |
| Caduceus + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 1,000 | 5,6% |
| Caduceus + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | 1,000 | 5,6% |
| Somente Comprimento (Atenção MIL) | 1,000 | 5,6% |
| Caduceus + Comprimento (Média $\rightarrow$ MLP) | 1,000 | 4,4% |
| 4-mers + Comprimento (Média $\rightarrow$ Projeção $\rightarrow$ MLP) | 1,000 | 3,3% |
| Caduceus (Média $\rightarrow$ Logística) | 1,000 | 3,3% |
| 4-mers + Comprimento (Projeção $\rightarrow$ Atenção MIL) | 1,000 | 3,3% |
| Caduceus — Resíduo após 4-mers (Logística) | 1,000 | 1,1% |
| Composição de 4-mers (Média $\rightarrow$ Logística) | 1,000 | 0,0% |

**Análise:** Sob controle estrito de falso-positivos, o método DELFI identifica 61,1% dos casos oncológicos externos, enquanto os modelos baseados em sequência não superam 5,6% de sensibilidade.

---

### 2.8. `controles_otimizacao.csv` — Estabilidade Numérica do Treinamento

Esta tabela reúne métricas de convergência das arquiteturas neurais ao longo do processo de descida de gradiente.

| Configuração Neural | Taxa Recorte Gradiente | Épocas Médias | Pico Parada Suave | Falhas de Otimização (AUROC < 0,60) |
| :--- | :---: | :---: | :---: | :---: |
| Caduceus + Comp. (Proj. $\rightarrow$ Média $\rightarrow$ MLP) | 0,001 | 22,6 | 0,700 | **6** |
| 4-mers + Comp. (Proj. $\rightarrow$ Média $\rightarrow$ MLP) | 0,009 | 25,1 | 0,751 | **4** |
| Caduceus + Comp. (Proj. $\rightarrow$ Atenção MIL) | 0,010 | 19,2 | 0,747 | **3** |
| 4-mers + Comp. (Proj. $\rightarrow$ Atenção MIL) | 0,027 | 17,4 | 0,744 | **3** |
| Somente Comprimento (Atenção MIL) | 0,012 | 25,5 | 0,728 | **1** |
| Caduceus + Comp. (Média $\rightarrow$ MLP) | 0,000 | 57,1 | 0,853 | **0** |
| Caduceus + Comp. (Média $\rightarrow$ Proj. $\rightarrow$ MLP) | 0,000 | 46,6 | 0,854 | **0** |
| 4-mers + Comp. (Média $\rightarrow$ Proj. $\rightarrow$ MLP) | 0,002 | 29,0 | 0,866 | **0** |
| Cobertura DELFI 5 Mb (MLP) | 0,000 | 7,3 | 0,859 | **0** |

**Análise:** Das 17 falhas totais de convergência observadas, 16 concentram-se nas redes que processam dados fragmento a fragmento. As redes que agregam por média antes das camadas densas não registraram falhas.

---

### 2.9. `auroc_por_semente.csv` — Variação entre Sementes

Esta tabela apresenta a AUROC média obtida nas 5 dobras para cada uma das sementes de inicialização nos modelos centrais.

| Semente Aleatória | DELFI (MLP) | Caduceus (Média $\rightarrow$ Proj. $\rightarrow$ MLP) | 4-mers (Média $\rightarrow$ Proj. $\rightarrow$ MLP) | Caduceus (Proj. $\rightarrow$ Atenção MIL) |
| :---: | :---: | :---: | :---: | :---: |
| `semente_1807` | 0,798 | 0,865 | 0,845 | 0,770 |
| `semente_2024` | 0,825 | 0,861 | 0,845 | 0,733 |
| `semente_3141` | 0,828 | 0,868 | 0,848 | 0,691 |
| `semente_5926` | 0,842 | 0,851 | 0,837 | 0,689 |
| `semente_8979` | 0,802 | 0,859 | 0,844 | 0,734 |
| **Média $\pm$ DP** | **0,819 $\pm$ 0,018** | **0,857 $\pm$ 0,009** | **0,844 $\pm$ 0,004** | **0,725 $\pm$ 0,033** |

**Análise:** O modelo com mecanismo de atenção exibe dispersão quatro vezes superior à do modelo linear de agregação prévia, variando de 0,689 a 0,770 em função da semente estocástica.

---

## 3. Reprodutibilidade e Manifesto Criptográfico

A integridade do fluxo analítico é verificada pelo arquivo `procedencia.json`, que registra os seguintes parâmetros de execução:
* **Assinatura SHA-256 dos dados brutos de entrada:** `897ce5eae3e362d8`
* **Ambiente computacional:** Kaggle, GPU NVIDIA Tesla T4 (tensores residentes em 3,83 GB de VRAM)
* **Tempo total de processamento:** 30,2 minutos
