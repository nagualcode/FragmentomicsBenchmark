#!/usr/bin/env bash
# =============================================================================
#  upload.sh  —  publica os estudos recortados como datasets PÚBLICOS no Kaggle
#                MODO ZIP: um arquivo por dataset, em vez de milhares de ficheiros
# =============================================================================
#
#  POR QUE ZIP RESOLVE O 403
#    A chamada CreateDatasetVersion valida, de uma vez, os tokens de TODOS os
#    ficheiros enviados. Com ~1.080 ficheiros e horas de upload, os primeiros 
#    tokens caducam antes do commit — e o Kaggle recusa com erro 403.
#    Com um único arquivo ZIP, há um único token e uma única entrada no commit.
#
#  POR QUE CONSTRUÍMOS O ZIP À MÃO
#    'zip -0' guarda sem comprimir. Os .bgz já são bgzip: comprimir outra vez
#    não ganha espaço e queima CPU desnecessariamente.
#
#  ESTRUTURA ENVIADA (4 ficheiros, nenhuma subpasta)
#    <slug>.zip            todos os .bgz e .tbi, com caminhos planos
#    manifest.csv          fora do zip, para ficar legível na página do Kaggle
#    CHECKSUMS.md5
#    dataset-metadata.json
#
#  USO
#    bash upload.sh --diagnostico
#    bash upload.sh cristiano2019_delfi_wgs --so-saudaveis    # ~2,5 GB
#    bash upload.sh cristiano2019_delfi_wgs --so-cancer       # o resto
#    bash upload.sh --verificar          # OBRIGATÓRIO depois de enviar
#    bash upload.sh --limpar
#
#  OPÇÕES ÚTEIS
#    --reusar-zip   não reconstrói o arquivo se já existir (para retentativas)
#    --sem-md5      salta os checksums
# =============================================================================
set -euo pipefail
export LC_ALL=C

_alvo="ok"; _eco="$_alvo"
[[ "$_eco" == "ok" ]] || { echo "ERRO: script corrompido na transferência."; exit 1; }

# ================= CONFIGURAÇÕES (AJUSTE CONFORME NECESSÁRIO) ================
RAIZ="/mnt/verde/cfdna/estudos_recortados"
PREPARO="/mnt/verde/cfdna/kaggle_preparo"
USUARIO="fredericoflores1807"  # <-- ALTERE PARA SEU USUÁRIO KAGGLE
REGISTO="$HOME/upload_kaggle_$(date +%Y%m%d_%H%M%S).log"
ESTUDOS_CONHECIDOS="jiang2015_hcc_wgs cristiano2019_delfi_wgs snyder2016_nucleosome_wgs sun2019_ocf_wgs"
RETENTATIVAS=3
ESPERA=180
# =============================================================================

slug_de() {
  case "$NOME" in
    jiang2015_hcc_wgs)         BASE="cfdna-jiang2015-hcc";         TIT="cfDNA Jiang 2015 HCC WGS" ;;
    cristiano2019_delfi_wgs)   BASE="cfdna-cristiano2019-delfi";   TIT="cfDNA Cristiano 2019 DELFI WGS" ;;
    snyder2016_nucleosome_wgs) BASE="cfdna-snyder2016-nucleosome"; TIT="cfDNA Snyder 2016 nucleosome WGS" ;;
    sun2019_ocf_wgs)           BASE="cfdna-sun2019-ocf";           TIT="cfDNA Sun 2019 OCF WGS" ;;
    *)                         BASE=""; TIT="" ;;
  esac
}

SIMULAR=0; INCLUIR_JIANG=0; SEM_MD5=0; VERIFICAR=0; LIMPAR=0
DIAGNOSTICO=0; SO_SAUDAVEIS=0; SO_CANCER=0; REUSAR_ZIP=0; PEDIDOS=""

for arg in "$@"; do
  case "$arg" in
    --simular)       SIMULAR=1 ;;
    --incluir-jiang) INCLUIR_JIANG=1 ;;
    --sem-md5)       SEM_MD5=1 ;;
    --verificar)     VERIFICAR=1 ;;
    --limpar)        LIMPAR=1 ;;
    --diagnostico)   DIAGNOSTICO=1 ;;
    --so-saudaveis)  SO_SAUDAVEIS=1 ;;
    --so-cancer)     SO_CANCER=1 ;;
    --reusar-zip)    REUSAR_ZIP=1 ;;
    -*) echo "opção desconhecida: $arg" >&2; exit 2 ;;
    *)  PEDIDOS="$PEDIDOS $arg" ;;
  esac
done

# Redireciona saída para log e terminal
exec > >(tee -a "$REGISTO") 2>&1
echo "=== upload para o Kaggle (modo zip, PÚBLICO) · $(date -Is) ==="
echo "registo: $REGISTO"

# Verificação de dependências (sem checagem de kaggle.json conforme solicitado)
command -v kaggle >/dev/null || { echo "ERRO: 'kaggle' não está no PATH"; exit 1; }
command -v zip    >/dev/null || { echo "ERRO: falta o 'zip'. Instale com: sudo apt install zip"; exit 1; }
command -v unzip  >/dev/null || { echo "ERRO: falta o 'unzip'. Instale com: sudo apt install unzip"; exit 1; }
command -v bc     >/dev/null || { echo "ERRO: falta o 'bc'. Instale com: sudo apt install bc"; exit 1; }

echo "kaggle CLI: $(kaggle --version 2>&1 | head -1)"

# =============================================================================
if [[ $DIAGNOSTICO -eq 1 ]]; then
  echo; echo "=== DATASETS DA CONTA ==="
  kaggle datasets list --mine -v 2>&1 | head -40 || echo "(falhou)"
  echo; echo "=== ESTADO DOS DATASETS DO PROJECTO ==="
  echo " 'processing' explica o 403: o Kaggle recusa versões enquanto processa."
  for NOME in $ESTUDOS_CONHECIDOS; do
    slug_de; [[ -n "$BASE" ]] || continue
    for S in "$BASE" "$BASE-healthy" "$BASE-cancer"; do
      printf " %-34s " "$S"
      kaggle datasets status "$USUARIO/$S" 2>&1 | head -1 || echo "(sem estado)"
    done
  done
  echo; echo "=== PREPARADO LOCALMENTE ==="
  [[ -d "$PREPARO" ]] && du -shL "$PREPARO"/*/ 2>/dev/null || echo " (nada)"
  echo; echo "=== ESPAÇO LIVRE ==="
  df -h "$PREPARO" 2>/dev/null || df -h /mnt/verde
  exit 0
fi

if [[ $LIMPAR -eq 1 ]]; then
  [[ -d "$PREPARO" ]] && { rm -rf "${PREPARO:?}"/*; echo "limpo."; } || echo "nada a limpar."
  exit 0
fi

if [[ $VERIFICAR -eq 1 ]]; then
  echo; echo "================================================================"
  echo " O QUE ESTÁ NO KAGGLE"
  echo "================================================================"
  kaggle datasets list --mine -v 2>&1 | grep -i cfdna || echo "(nenhum cfdna)"
  echo
  echo "================================================================"
  echo " O KAGGLE EXTRAIU OS ZIPS?  ← a pergunta que importa"
  echo "================================================================"
  for NOME in $ESTUDOS_CONHECIDOS; do
    slug_de; [[ -n "$BASE" ]] || continue
    for S in "$BASE" "$BASE-healthy" "$BASE-cancer"; do
      L=$(kaggle datasets files "$USUARIO/$S" 2>/dev/null || true)
      [[ -n "$L" ]] || continue
      N=$(echo "$L" | tail -n +2 | grep -c . || true)
      Z=$(echo "$L" | grep -c '\.zip' || true)
      B=$(echo "$L" | grep -c '\.bgz' || true)
      printf " %-34s %3s entradas · %s .zip · %s .bgz  " "$S" "$N" "$Z" "$B"
      if   [[ "$B" -gt 0 ]]; then echo "✓ EXTRAIU — o notebook vai funcionar"
      elif [[ "$Z" -gt 0 ]]; then echo "✗ NÃO EXTRAIU — precisa do plano B"
      else                        echo "? confira na página do dataset"
      fi
    done
  done
  echo
  echo " A listagem do CLI pagina. Para a contagem exacta abra a página:"
  echo "   https://www.kaggle.com/datasets/$USUARIO/<slug>"
  echo
  echo " Se disser NÃO EXTRAIU, use o bloco de contingência do notebook."
  exit 0
fi

# --- fila --------------------------------------------------------------------
if [[ -n "${PEDIDOS// /}" ]]; then FILA="$PEDIDOS"; else
  FILA=""
  for NOME in $ESTUDOS_CONHECIDOS; do
    [[ -d "$RAIZ/$NOME" ]] || continue
    [[ "$NOME" == "jiang2015_hcc_wgs" && $INCLUIR_JIANG -eq 0 ]] && continue
    FILA="$FILA $NOME"
  done
fi
echo; echo "fila:$FILA"
[[ -n "${FILA// /}" ]] || { echo "nada a fazer."; exit 0; }

CONCLUIDOS=""; REPROVADOS=""

for NOME in $FILA; do
  DIR="$RAIZ/$NOME"
  echo; echo "────────────────────────────────────────────────────────────────"
  echo "ESTUDO: $NOME"
  echo "────────────────────────────────────────────────────────────────"
  [[ -d "$DIR" ]] || { echo "  ✗ inexistente"; REPROVADOS="$REPROVADOS $NOME"; continue; }
  slug_de
  [[ -n "$BASE" ]] || { echo "  ✗ sem slug"; REPROVADOS="$REPROVADOS $NOME"; continue; }

  # --- selecção das amostras -------------------------------------------------
  LISTA=$(mktemp); SUFIXO=""
  if   [[ $SO_SAUDAVEIS -eq 1 ]]; then
    find "$DIR" -type f -name '*.frag.tsv.bgz' -path '*/healthy/*' | sort > "$LISTA"
    SUFIXO="-healthy"; echo "  · modo --so-saudaveis"
  elif [[ $SO_CANCER -eq 1 ]]; then
    find "$DIR" -type f -name '*.frag.tsv.bgz' ! -path '*/healthy/*' | sort > "$LISTA"
    SUFIXO="-cancer";  echo "  · modo --so-cancer"
  else
    find "$DIR" -type f -name '*.frag.tsv.bgz' | sort > "$LISTA"
  fi
  SLUG="${BASE}${SUFIXO}"
  N_BGZ=$(wc -l < "$LISTA")
  [[ "$N_BGZ" -gt 0 ]] || { echo "  ✗ nenhuma amostra seleccionada"; rm -f "$LISTA"
                            REPROVADOS="$REPROVADOS $NOME"; continue; }
  echo "  · amostras: $N_BGZ  →  $USUARIO/$SLUG"

  # --- índices .tbi ----------------------------------------------------------
  SEM_IDX=0
  while IFS= read -r A; do [[ -f "${A}.tbi" ]] || SEM_IDX=$((SEM_IDX+1)); done < "$LISTA"
  if [[ "$SEM_IDX" -gt 0 ]]; then
    echo "  ✗ $SEM_IDX ficheiro(s) sem .tbi — refaça 'tabix -p bed'"
    rm -f "$LISTA"; REPROVADOS="$REPROVADOS $NOME"; continue
  fi
  echo "  · índices .tbi: todos presentes"

  # --- colisão de nomes ao achatar -------------------------------------------
  N_UNI=$(sed 's|.*/||' "$LISTA" | sort -u | wc -l)
  if [[ "$N_UNI" -ne "$N_BGZ" ]]; then
    echo "  ✗ colisão de nomes: $N_BGZ ficheiros, $N_UNI nomes únicos"
    sed 's|.*/||' "$LISTA" | sort | uniq -d | head
    rm -f "$LISTA"; REPROVADOS="$REPROVADOS $NOME"; continue
  fi
  echo "  · nomes únicos: OK"

  ALVO="$PREPARO/$SLUG"; ZIPF="$ALVO/${SLUG}.zip"
  mkdir -p "$ALVO"

  # --- espaço livre ----------------------------------------------------------
  BYTES=$(while IFS= read -r A; do
            stat -c%s "$A"; [[ -f "${A}.tbi" ]] && stat -c%s "${A}.tbi"
          done < "$LISTA" | awk '{s+=$1} END{print s+0}')
  LIVRE=$(df -B1 --output=avail "$ALVO" | tail -1)
  printf "  · dados %.2f GB · livre %.2f GB\n" \
         "$(echo "$BYTES/1000000000" | bc -l)" "$(echo "$LIVRE/1000000000" | bc -l)"
  if [[ "$LIVRE" -lt $((BYTES + 500000000)) ]]; then
    echo "  ✗ espaço insuficiente. Use --so-saudaveis / --so-cancer para dividir,"
    echo "    ou liberte espaço com: bash upload.sh --limpar"
    rm -f "$LISTA"; REPROVADOS="$REPROVADOS $NOME"; continue
  fi

  # --- construir o arquivo ---------------------------------------------------
  if [[ -f "$ZIPF" && $REUSAR_ZIP -eq 1 ]]; then
    echo "  · a reutilizar o zip existente (--reusar-zip)"
  else
    rm -f "$ZIPF"
    echo "  · a construir o arquivo sem compressão (limitado pelo disco)…"
    T0=$(date +%s)
    while IFS= read -r A; do
      echo "$A"; [[ -f "${A}.tbi" ]] && echo "${A}.tbi"
    done < "$LISTA" | zip -0 -X -j -q "$ZIPF" -@
    echo "  · zip pronto em $(( ($(date +%s)-T0)/60 )) min"
  fi

  # --- conferir o arquivo ANTES de gastar horas de upload --------------------
  N_ZIP=$(unzip -l "$ZIPF" | tail -1 | awk '{print $2}')
  ESPERADO=$((N_BGZ*2))
  echo "  · o arquivo contém $N_ZIP entradas (esperado $ESPERADO)"
  if [[ "$N_ZIP" -ne "$ESPERADO" ]]; then
    echo "  ✗ contagem errada no arquivo — não enviado"
    rm -f "$LISTA"; REPROVADOS="$REPROVADOS $NOME"; continue
  fi
  if unzip -l "$ZIPF" | grep -q '/'; then
    echo "  ✗ o arquivo tem caminhos com subpastas; '-j' deveria tê-los removido"
    rm -f "$LISTA"; REPROVADOS="$REPROVADOS $NOME"; continue
  fi
  echo "  · caminhos planos confirmados"

  # --- manifesto, fora do zip para ficar legível na página -------------------
  { echo "sample_id,condicao,estudo,arquivo"
    while IFS= read -r A; do
      B=$(basename "$A")
      echo "${B%%.*},$(basename "$(dirname "$A")"),$NOME,$B"
    done < "$LISTA"
  } > "$ALVO/manifest.csv"
  echo "  · manifest.csv: $(( $(wc -l < "$ALVO/manifest.csv") - 1 )) linhas"
  echo "  · condições: $(tail -n +2 "$ALVO/manifest.csv" | cut -d, -f2 \
                          | sort | uniq -c | tr '\n' ' ')"

  if [[ $SEM_MD5 -eq 0 ]]; then
    ( cd "$ALVO" && md5sum "${SLUG}.zip" manifest.csv > CHECKSUMS.md5 )
  fi
  printf '{\n  "title": "%s%s (promoter-trimmed)",\n  "id": "%s/%s",\n  "licenses": [{"name": "CC0-1.0"}]\n}\n' \
    "$TIT" "$SUFIXO" "$USUARIO" "$SLUG" > "$ALVO/dataset-metadata.json"

  N_ARQ=$(find "$ALVO" -maxdepth 1 -type f | wc -l)
  N_SUB=$(find "$ALVO" -mindepth 1 -type d | wc -l)
  echo "  · a enviar: $N_ARQ ficheiros, $N_SUB subpastas, $(du -shL "$ALVO" | cut -f1)"
  [[ "$N_SUB" -eq 0 ]] || { echo "  ✗ subpasta na área de envio"; rm -f "$LISTA"
                            REPROVADOS="$REPROVADOS $NOME"; continue; }
  rm -f "$LISTA"

  if [[ $SIMULAR -eq 1 ]]; then
    echo "  · [simulação] enviaria $N_ARQ ficheiros para $USUARIO/$SLUG"
    CONCLUIDOS="$CONCLUIDOS $NOME"; continue
  fi

  # --- decisão explícita: criar ou versionar, nunca as duas -----------------
  if kaggle datasets list --mine -s "$SLUG" 2>/dev/null | grep -q "$USUARIO/$SLUG$"; then
    ACCAO="version"; echo "  · dataset existe → nova versão"
  else
    ACCAO="create";  echo "  · dataset novo → criar (PÚBLICO)"
  fi

  OK=0; ERRO=$(mktemp)
  for (( T=1; T<=RETENTATIVAS; T++ )); do
    echo "  · tentativa $T/$RETENTATIVAS ($ACCAO) — um ficheiro grande, seja paciente"
    set +e
    if [[ "$ACCAO" == "create" ]]; then
      # --public garante que o dataset seja criado como público
      kaggle datasets create -p "$ALVO" --dir-mode skip --public 2>&1 | tee "$ERRO"
    else
      kaggle datasets version -p "$ALVO" --dir-mode skip \
        -m "arquivo único, sem compressão · $(date -Is)" 2>&1 | tee "$ERRO"
    fi
    set -e
    if grep -qiE '40[0-9] Client Error|forbidden|exceeded|error' "$ERRO"; then
      if grep -qi 'already exists' "$ERRO"; then
        echo "    → já existe; a mudar para 'version'"; ACCAO="version"; continue
      fi
      if grep -q '403' "$ERRO"; then
        echo "    → 403: o Kaggle costuma ainda estar a processar a versão"
        echo "      anterior. A esperar ${ESPERA}s antes de repetir…"
        [[ "$T" -lt "$RETENTATIVAS" ]] && sleep "$ESPERA"
        continue
      fi
      echo "    → erro não recuperável; a mensagem completa está acima"
      break
    fi
    OK=1; break
  done
  rm -f "$ERRO"

  if [[ "$OK" -eq 1 ]]; then
    echo "  ✓ enviado — AGORA CORRA:  bash upload.sh --verificar"
    CONCLUIDOS="$CONCLUIDOS $NOME"
  else
    echo "  ✗ falhou. O zip fica em $ZIPF; repita com --reusar-zip para não"
    echo "    o reconstruir."
    REPROVADOS="$REPROVADOS $NOME"
  fi
done

echo
echo "================================================================"
echo " RESUMO · $(date -Is)"
echo "================================================================"
echo " concluídos :${CONCLUIDOS:- nenhum}"
echo " reprovados :${REPROVADOS:- nenhum}"
echo
echo " PASSO OBRIGATÓRIO:   bash upload.sh --verificar"
echo " Ele responde à única pergunta que resta: o Kaggle extraiu o zip?"
[[ -z "${REPROVADOS// /}" ]] || exit 1
exit 0
