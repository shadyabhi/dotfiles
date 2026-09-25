# Merge semantics for chezmoi modify scripts. See .json_merges/merge.sh and
# the "Readable JSON overlays" plan for the contract these implement.
#
# deepfill(live; defaults): fill in paths missing from `live`, recursing into
# objects. Never overwrites a value `live` already has (e.g. a plugin the
# user disabled locally stays disabled).
def deepfill(a; d):
  if (a | type) == "object" and (d | type) == "object" then
    reduce (d | keys_unsorted[]) as $k (a;
      if (a | has($k)) then
        if (a[$k] | type) == "object" and (d[$k] | type) == "object" then
          .[$k] = deepfill(a[$k]; d[$k])
        else . end
      else .[$k] = d[$k] end)
  else a end;

# deepmerge(base; overlay): recursive merge where the overlay wins on
# scalars/objects (including `false`/`0`, unlike sprig's merge), keeps
# base's key order and appends new overlay keys at the end, and unions
# arrays by deep equality (base items first in base order, then overlay
# items not already present, in overlay order) instead of replacing them.
def deepmerge(a; b):
  if (a | type) == "object" and (b | type) == "object" then
    reduce (b | keys_unsorted[]) as $k (a;
      if (a | has($k)) then
        .[$k] = deepmerge(a[$k]; b[$k])
      else .[$k] = b[$k] end)
  elif (a | type) == "array" and (b | type) == "array" then
    a + (b - a)
  else b end;

# deepremove(base; removals): drop paths listed in `removals`. A key mapped
# to null deletes that key entirely; a key mapped to an array removes those
# array elements (by deep equality) from base's array at that path; a key
# mapped to an object recurses.
def deepremove(a; r):
  if (r | type) == "object" and (a | type) == "object" then
    reduce (r | keys_unsorted[]) as $k (a;
      if (r[$k] == null) then del(.[$k])
      elif (a | has($k)) then
        if (a[$k] | type) == "array" and (r[$k] | type) == "array" then
          .[$k] = (a[$k] - r[$k])
        else .[$k] = deepremove(a[$k]; r[$k]) end
      else . end)
  else a end;
