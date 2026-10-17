// Dynamic selector states kept in the native node (e.fmt.css.match reads them): checkedness, indeterminate, :popover-open,
// :defined, :focus and :focus-within, :modal.
const F_CHECKED_AUTH = 1, F_CHECKED = 2, F_INDETERMINATE = 4, F_POPOVER_OPEN = 8, F_DEFINED = 16, F_FOCUS = 32, F_FOCUS_WITHIN = 64, F_MODAL = 128;
function setNodeFlags(el, mask, on) { N.setFlags(idOf(el), mask, !!on); }
function nodeFlag(el, mask) { return (N.flags(idOf(el)) & mask) !== 0; }
