#!/bin/bash
# ==============================================================================
# recorta_painel.sh                                                  v2.0
#
#   Recorta os arquivos de fragmentos do FinaleDB para o painel de regioes
#   promotoras, preservando a organizacao  estudo/condicao/ .
#   Reducao esperada: ~280 GB -> ~12 GB.
#
# ------------------------------------------------------------------------------
# CORRECOES EM RELACAO A v1.0
#
#   [C1] LC_ALL=C obrigatorio. A ordenacao de arquivos BED depende do locale;
#        sob pt_BR.UTF-8 a colacao pode divergir e produzir um indice tabix
#        inconsistente SEM emitir erro.
#
#   [C2] Invariante de distancia REAPLICADA apos o subtract. O 'bedtools
#        subtract' pode partir um intervalo do painel em dois pedacos separados
#        por uma regiao estreita da blacklist. Se essa separacao for menor que o
#        comprimento maximo de fragmento (300 pb), um mesmo fragmento intersecta
#        os dois pedacos e o 'tabix -R' o emite DUAS VEZES — duplicata artificial
#        nas contagens de clivagem. Por isso refundimos com -d 500 apos o
#        subtract e VERIFICAMOS a invariante antes de prosseguir.
#        (Reintroduzir algumas bases da blacklist e inocuo: o notebook aplica o
#        filtro de blacklist na selecao dos loci.)
#
#   [C3] Despacho paralelo simplificado. A v1.0 passava dois campos por xargs via
#        here-string com IFS, o que quebra com espacos no caminho. Agora o worker
#        recebe apenas a origem e deriva o destino.
#
#   [C4] Aritmetica de shell corrigida (a v1.0 usava ${((...))}, sintaxe invalida)
#        e 'sort' com limite de memoria e TMPDIR explicito, necessario sob -j alto.
# ------------------------------------------------------------------------------
# USO
#   ./recorta_painel.sh                        # simulacao
#   ./recorta_painel.sh --apply                # executa
#   ./recorta_painel.sh --apply -j 24          # 24 processos
#   ./recorta_painel.sh --apply --forcar       # refaz arquivos ja existentes
#   ./recorta_painel.sh --apply --estudos "jiang2015_hcc_wgs"
#   ./recorta_painel.sh --verificar            # so audita a saida existente
# ==============================================================================
set -uo pipefail

# ----------------------------- [C1] AMBIENTE ----------------------------------
export LC_ALL=C
export LANG=C
export TMPDIR="${TMPDIR:-/tmp}"
export SORT_MEM="${SORT_MEM:-256M}"

# ---------------------------- CONFIGURACAO ------------------------------------
export ORIGEM="${ORIGEM:-/mnt/verde/cfdna/estudos}"
export DESTINO="${DESTINO:-/mnt/verde/cfdna/estudos_recortados}"
REFDIR="${REFDIR:-/mnt/verde/cfdna/referencia}"
PLS_BED="$REFDIR/GRCh38-PLS.bed"
BLACKLIST="$REFDIR/ENCFF356LFX.bed"
export PAINEL="$REFDIR/painel_ext.bed"

FLANCO=2048             # +-2 kb ao redor do centro de cada promotor
MERGE_DIST=500          # folga minima entre intervalos (> 300 pb = frag. maximo)
MIN_INTERVALO=200       # descarta fragmentos de painel muito curtos
FRAG_MAX=300            # comprimento maximo de fragmento considerado a jusante
EXCLUIR_ESTUDOS="adalsteinsson2017_mbc_mcrpc_wes burnham_rabinowitz_urina_prenatal"

# contagens esperadas (Tabela Suplementar 1 do FinaleDB)
declare -A ESPERADO=(
  [jiang2015_hcc_wgs]=225
  [cristiano2019_delfi_wgs]=538
  [snyder2016_nucleosome_wgs]=60
  [sun2019_ocf_wgs]=31
)

APLICAR=0; FORCAR=0; SO_VERIFICAR=0
JOBS=$(nproc 2>/dev/null || echo 8)
FILTRO_ESTUDOS=""
while [ $# -gt 0 ]; do
  case "\$1" in
    --apply)     APLICAR=1; shift ;;
    --forcar)    FORCAR=1; shift ;;
    --verificar) SO_VERIFICAR=1; shift ;;
    --estudos)   FILTRO_ESTUDOS="\$2"; shift 2 ;;
    -j)          JOBS="\$2"; shift 2 ;;
    *) echo "argumento desconhecido: \$1"; exit 1 ;;
  esac
done
export FORCAR

for c in tabix bgzip bedtools awk sort find xargs; do
  command -v "$c" >/dev/null || { echo "ERRO: '$c' nao encontrado"; exit 1; }
done
tabix 2>&1 | grep -q '\-R' || { echo "ERRO: seu tabix nao suporta -R"; exit 1; }

echo "=============================================================="
echo " recorta_painel.sh v2.0"
echo " Origem    : $ORIGEM"
echo " Destino   : $DESTINO"
echo " Painel    : $PAINEL  (+-${FLANCO} pb, folga ${MERGE_DIST} pb)"
echo " Processos : $JOBS   | sort: -S $SORT_MEM -T $TMPDIR | LC_ALL=$LC_ALL"
echo " Modo      : $( ((SO_VERIFICAR)) && echo VERIFICACAO || { ((APLICAR)) && echo EXECUCAO || echo SIMULACAO; } )"
echo "=============================================================="

# ==============================================================================
# 1. PAINEL  — construcao e validacao da invariante [C2]
# ==============================================================================
construir_painel() {
  local tmp1 tmp2
  tmp1="$(mktemp)"; tmp2="$(mktemp)"

  # 1.1 expandir cada promotor autossomico para +-FLANCO em torno do centro
  awk -v F="$FLANCO" 'BEGIN{OFS="\t"}
      \$1 ~ /^chr([1-9]|1[0-9]|2[0-2])$/ {
        m = int((\$2+\$3)/2); s = m-F; if (s<0) s=0; print \$1, s, m+F }' "$PLS_BED" \
    | sort -S "$SORT_MEM" -T "$TMPDIR" -k1,1 -k2,2n \
    | bedtools merge -d "$MERGE_DIST" -i - > "$tmp1"

  # 1.2 remover a ENCODE blacklist
  bedtools subtract -a "$tmp1" -b "$BLACKLIST" \
    | sort -S "$SORT_MEM" -T "$TMPDIR" -k1,1 -k2,2n > "$tmp2"

  # 1.3 [C2] REAPLICAR a invariante: o subtract pode ter criado pedacos proximos
  bedtools merge -d "$MERGE_DIST" -i "$tmp2" \
    | awk -v L="$MIN_INTERVALO" 'BEGIN{OFS="\t"} \$3-\$2 >= L' \
    | sort -S "$SORT_MEM" -T "$TMPDIR" -k1,1 -k2,2n > "$PAINEL"

  rm -f "$tmp1" "$tmp2"
}

if [ ! -s "$PAINEL" ]; then
  echo "[painel] construindo..."
  [ -s "$PLS_BED" ]   || { echo "ERRO: ausente $PLS_BED"; exit 1; }
  [ -s "$BLACKLIST" ] || { echo "ERRO: ausente $BLACKLIST"; exit 1; }
  construir_painel
else
  echo "[painel] reutilizando $PAINEL"
fi

# validacao da invariante — bloqueante
VIOL=$(awk -v F="$FRAG_MAX" '
  { if (\$1==pc && (\$2-pe) <= F) v++; pc=\$1; pe=\$3 }
  END{ print v+0 }' "$PAINEL")
awk -v n_pls="$(awk '\$1 ~ /^chr([1-9]|1[0-9]|2[0-2])$/' "$PLS_BED" | wc -l)" '
  {n++; b+=\$3-\$2; if(\$3-\$2<mn||n==1)mn=\$3-\$2; if(\$3-\$2>mx)mx=\$3-\$2}
  END{
    printf "[painel] promotores PLS autossomicos : %d\n", n_pls
    printf "[painel] intervalos finais           : %d\n", n
    printf "[painel] extensao total              : %.1f Mb (%.2f%% do genoma)\n", b/1e6, 100*b/3.1e9
    printf "[painel] tamanho de intervalo        : min %d / max %d pb\n", mn, mx
  }' "$PAINEL"
echo "[painel] pares de intervalos a <= ${FRAG_MAX} pb : $VIOL"
if [ "$VIOL" -ne 0 ]; then
  echo
  echo "ERRO BLOQUEANTE: a invariante de distancia foi violada em $VIOL pares."
  echo "  Um fragmento de ate ${FRAG_MAX} pb poderia intersectar dois intervalos"
  echo "  e ser emitido duas vezes pelo tabix -R, criando duplicatas artificiais."
  echo "  Aumente MERGE_DIST (atual: $MERGE_DIST) e apague $PAINEL para reconstruir."
  exit 1
fi
echo "[painel] invariante OK — nenhum fragmento pode ser emitido em duplicidade."
md5sum "$PAINEL" | tee "$REFDIR/painel_ext.bed.md5"
echo "[painel] este md5 deve ser conferido no notebook (dataset cfdna-ref-hg38)."

# ==============================================================================
# 2. WORKER  [C3]
# ==============================================================================
recorta_um() {
  local src="\$1"
  local rel="${src#"$ORIGEM"/}"
  local dst="$DESTINO/$rel"
  local dir; dir="$(dirname "$dst")"

  # retomada
  if [ "$FORCAR" -eq 0 ] && [ -s "$dst" ] && [ -s "$dst.tbi" ]; then
    if tabix -l "$dst" >/dev/null 2>&1; then
      printf 'PULADO|%s|0|%s\n' "$src" "$(stat -c%s "$dst")"; return 0
    fi
  fi
  [ -s "$src.tbi" ] || { printf 'SEM_INDICE|%s|0|0\n' "$src"; return 1; }

  mkdir -p "$dir" 2>/dev/null
  local tmp="${dst}.parcial.$$"

  if ! tabix -R "$PAINEL" "$src" 2>/dev/null \
        | sort -S "$SORT_MEM" -T "$TMPDIR" -k1,1 -k2,2n \
        | bgzip -c > "$tmp"; then
    rm -f "$tmp"; printf 'FALHA_RECORTE|%s|0|0\n' "$src"; return 1
  fi
  if [ ! -s "$tmp" ]; then
    rm -f "$tmp"; printf 'VAZIO|%s|0|0\n' "$src"; return 1
  fi
  if ! tabix -p bed -f "$tmp" 2>/dev/null; then
    rm -f "$tmp" "$tmp.tbi"; printf 'FALHA_INDICE|%s|0|0\n' "$src"; return 1
  fi
  if [ -z "$(tabix -l "$tmp" 2>/dev/null | head -1)" ]; then
    rm -f "$tmp" "$tmp.tbi"; printf 'INDICE_VAZIO|%s|0|0\n' "$src"; return 1
  fi

  mv -f "$tmp" "$dst"; mv -f "$tmp.tbi" "$dst.tbi"
  printf 'OK|%s|%s|%s\n' "$src" "$(stat -c%s "$src")" "$(stat -c%s "$dst")"
}
export -f recorta_um

# ==============================================================================
# 3. SELECAO DE ARQUIVOS
# ==============================================================================
LISTA="$(mktemp)"
while IFS= read -r -d '' src; do
  rel="${src#"$ORIGEM"/}"; est="${rel%%/*}"
  pular=0
  for e in $EXCLUIR_ESTUDOS; do [ "$est" = "$e" ] && pular=1; done
  if [ -n "$FILTRO_ESTUDOS" ]; then
    inc=0; for e in $FILTRO_ESTUDOS; do [ "$est" = "$e" ] && inc=1; done
    [ "$inc" -eq 0 ] && pular=1
  fi
  [ "$pular" -eq 1 ] && continue
  printf '%s\0' "$src" >> "$LISTA"
done < <(find "$ORIGEM" -type f -name "*.frag.tsv.bgz" -print0)

TOTAL=$(tr -cd '\0' < "$LISTA" | wc -c)
echo
echo "[tarefas] $TOTAL arquivos selecionados"
echo "[tarefas] estudos excluidos: $EXCLUIR_ESTUDOS"
tr '\0' '\n' < "$LISTA" | awk -F/ '{print $(NF-2)"/"$(NF-1)}' \
  | sort | uniq -c | awk '{printf "  %-6s %s\n", \$1, \$2}'
[ "$TOTAL" -eq 0 ] && { echo "Nada a fazer."; rm -f "$LISTA"; exit 0; }

if ((SO_VERIFICAR==0)) && ((APLICAR==0)); then
  echo; echo ">>> SIMULACAO. Nada foi escrito. Use --apply para executar."
  rm -f "$LISTA"; exit 0
fi

# ==============================================================================
# 4. EXECUCAO PARALELA + PROGRESSO
# ==============================================================================
mkdir -p "$DESTINO"
LOG="$DESTINO/recorte_$(date +%Y%m%d_%H%M%S).log"

if ((SO_VERIFICAR==0)); then
  echo; echo "[recorte] iniciando ($JOBS processos) — log: $LOG"
  : > "$LOG"
  ( while sleep 30; do
      [ -f "$LOG" ] || break
      d=$(grep -c '^OK|\|^PULADO|' "$LOG" 2>/dev/null || echo 0)
      printf '\r  progresso: %d/%d  (%d%%)   ' "$d" "$TOTAL" $(( d*100/TOTAL ))
    done ) &
  PROG=$!
  t0=$(date +%s)

  xargs -0 -a "$LISTA" -P "$JOBS" -I{} \
        bash -c 'recorta_um "\$1"' _ {} >> "$LOG" 2>&1

  t1=$(date +%s)
  kill "$PROG" 2>/dev/null; wait "$PROG" 2>/dev/null
  printf '\r%*s\r' 60 ''
  MIN=$(( (t1-t0) / 60 )); SEG=$(( (t1-t0) % 60 ))
else
  LOG="$(ls -t "$DESTINO"/recorte_*.log 2>/dev/null | head -1)"
  MIN=0; SEG=0
fi
rm -f "$LISTA"

# ==============================================================================
# 5. RELATORIO
# ==============================================================================
echo
echo "=============================================================="
echo " RELATORIO   (${MIN}m ${SEG}s)"
echo "=============================================================="
if [ -s "${LOG:-}" ]; then
  awk -F'|' '
    {st[\$1]++}
    \$1=="OK" {so+=\$3; sd+=\$4; n++}
    END{
      print "  situacao por arquivo:"
      for (k in st) printf "    %-14s %d\n", k, st[k]
      if (n>0) {
        printf "\n  volume original  : %.2f GB\n", so/1073741824
        printf "  volume recortado : %.2f GB\n", sd/1073741824
        printf "  fator de reducao : %.1fx\n", so/sd
      }
    }' "$LOG"
  echo
  PROB=$(grep -vc '^OK|\|^PULADO|' "$LOG" 2>/dev/null || echo 0)
  if [ "$PROB" -gt 0 ]; then
    echo "  PROBLEMAS ($PROB):"
    grep -v '^OK|\|^PULADO|' "$LOG" | head -25 | awk -F'|' '{printf "    %-14s %s\n", \$1, \$2}'
  fi
fi

# ------------------------- 5.1 conferencia de contagens -----------------------
echo
echo " CONFERENCIA CONTRA A TABELA SUPLEMENTAR 1 DO FinaleDB"
FALHOU=0
for est in "${!ESPERADO[@]}"; do
  [ -d "$DESTINO/$est" ] || continue
  obt=$(find "$DESTINO/$est" -name "*.frag.tsv.bgz" | wc -l)
  esp=${ESPERADO[$est]}
  if [ "$obt" -eq "$esp" ]; then mark="OK"; else mark="DIVERGENTE"; FALHOU=1; fi
  printf "  %-30s esperado=%-5s obtido=%-5s %s\n" "$est" "$esp" "$obt" "$mark"
done

# ------------------------- 5.2 auditoria de integridade -----------------------
echo
echo " AUDITORIA DE INTEGRIDADE (todos os arquivos de saida)"
n_ok=0; n_ruim=0
while IFS= read -r -d '' f; do
  if [ -s "$f" ] && [ -s "$f.tbi" ] && tabix -l "$f" >/dev/null 2>&1; then
    n_ok=$((n_ok+1))
  else
    n_ruim=$((n_ruim+1)); echo "    CORROMPIDO: $f"
  fi
done < <(find "$DESTINO" -type f -name "*.frag.tsv.bgz" -print0)
echo "  indices validos: $n_ok | problematicos: $n_ruim"
find "$DESTINO" -name "*.parcial.*" -print -delete 2>/dev/null | sed 's/^/    removido temporario: /'

# ------------------------- 5.3 estrutura e tamanho ----------------------------
echo
echo " ESTRUTURA GERADA"
du -h --max-depth=2 "$DESTINO" 2>/dev/null | sort -k2 | sed 's/^/  /'
echo
df -h "$DESTINO" | tail -1 | awk '{print "  espaco livre restante: " \$4}'
echo
echo " log: $LOG"
echo "=============================================================="
if [ "$n_ruim" -eq 0 ] && [ "$FALHOU" -eq 0 ]; then
  echo " RECORTE CONCLUIDO COM SUCESSO — pode rodar sobe_datasets_kaggle.sh"
else
  echo " HA PENDENCIAS — revise os itens acima antes de subir ao Kaggle."
fi
echo "=============================================================="
