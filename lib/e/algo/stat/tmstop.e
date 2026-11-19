// tm stopwords("english") (the SMART-free Snowball list tm ships), generated from tm and sorted: is_stopword_en answers by binary search.

use e.mem
use e.str

const STOP_EN_N = 174usize

fn stop_en_at(i: usize) -> str {
    if i == 0usize { ret "a" }
    if i == 1usize { ret "about" }
    if i == 2usize { ret "above" }
    if i == 3usize { ret "after" }
    if i == 4usize { ret "again" }
    if i == 5usize { ret "against" }
    if i == 6usize { ret "all" }
    if i == 7usize { ret "am" }
    if i == 8usize { ret "an" }
    if i == 9usize { ret "and" }
    if i == 10usize { ret "any" }
    if i == 11usize { ret "are" }
    if i == 12usize { ret "aren't" }
    if i == 13usize { ret "as" }
    if i == 14usize { ret "at" }
    if i == 15usize { ret "be" }
    if i == 16usize { ret "because" }
    if i == 17usize { ret "been" }
    if i == 18usize { ret "before" }
    if i == 19usize { ret "being" }
    if i == 20usize { ret "below" }
    if i == 21usize { ret "between" }
    if i == 22usize { ret "both" }
    if i == 23usize { ret "but" }
    if i == 24usize { ret "by" }
    if i == 25usize { ret "can't" }
    if i == 26usize { ret "cannot" }
    if i == 27usize { ret "could" }
    if i == 28usize { ret "couldn't" }
    if i == 29usize { ret "did" }
    if i == 30usize { ret "didn't" }
    if i == 31usize { ret "do" }
    if i == 32usize { ret "does" }
    if i == 33usize { ret "doesn't" }
    if i == 34usize { ret "doing" }
    if i == 35usize { ret "don't" }
    if i == 36usize { ret "down" }
    if i == 37usize { ret "during" }
    if i == 38usize { ret "each" }
    if i == 39usize { ret "few" }
    if i == 40usize { ret "for" }
    if i == 41usize { ret "from" }
    if i == 42usize { ret "further" }
    if i == 43usize { ret "had" }
    if i == 44usize { ret "hadn't" }
    if i == 45usize { ret "has" }
    if i == 46usize { ret "hasn't" }
    if i == 47usize { ret "have" }
    if i == 48usize { ret "haven't" }
    if i == 49usize { ret "having" }
    if i == 50usize { ret "he" }
    if i == 51usize { ret "he'd" }
    if i == 52usize { ret "he'll" }
    if i == 53usize { ret "he's" }
    if i == 54usize { ret "her" }
    if i == 55usize { ret "here" }
    if i == 56usize { ret "here's" }
    if i == 57usize { ret "hers" }
    if i == 58usize { ret "herself" }
    if i == 59usize { ret "him" }
    if i == 60usize { ret "himself" }
    if i == 61usize { ret "his" }
    if i == 62usize { ret "how" }
    if i == 63usize { ret "how's" }
    if i == 64usize { ret "i" }
    if i == 65usize { ret "i'd" }
    if i == 66usize { ret "i'll" }
    if i == 67usize { ret "i'm" }
    if i == 68usize { ret "i've" }
    if i == 69usize { ret "if" }
    if i == 70usize { ret "in" }
    if i == 71usize { ret "into" }
    if i == 72usize { ret "is" }
    if i == 73usize { ret "isn't" }
    if i == 74usize { ret "it" }
    if i == 75usize { ret "it's" }
    if i == 76usize { ret "its" }
    if i == 77usize { ret "itself" }
    if i == 78usize { ret "let's" }
    if i == 79usize { ret "me" }
    if i == 80usize { ret "more" }
    if i == 81usize { ret "most" }
    if i == 82usize { ret "mustn't" }
    if i == 83usize { ret "my" }
    if i == 84usize { ret "myself" }
    if i == 85usize { ret "no" }
    if i == 86usize { ret "nor" }
    if i == 87usize { ret "not" }
    if i == 88usize { ret "of" }
    if i == 89usize { ret "off" }
    if i == 90usize { ret "on" }
    if i == 91usize { ret "once" }
    if i == 92usize { ret "only" }
    if i == 93usize { ret "or" }
    if i == 94usize { ret "other" }
    if i == 95usize { ret "ought" }
    if i == 96usize { ret "our" }
    if i == 97usize { ret "ours" }
    if i == 98usize { ret "ourselves" }
    if i == 99usize { ret "out" }
    if i == 100usize { ret "over" }
    if i == 101usize { ret "own" }
    if i == 102usize { ret "same" }
    if i == 103usize { ret "shan't" }
    if i == 104usize { ret "she" }
    if i == 105usize { ret "she'd" }
    if i == 106usize { ret "she'll" }
    if i == 107usize { ret "she's" }
    if i == 108usize { ret "should" }
    if i == 109usize { ret "shouldn't" }
    if i == 110usize { ret "so" }
    if i == 111usize { ret "some" }
    if i == 112usize { ret "such" }
    if i == 113usize { ret "than" }
    if i == 114usize { ret "that" }
    if i == 115usize { ret "that's" }
    if i == 116usize { ret "the" }
    if i == 117usize { ret "their" }
    if i == 118usize { ret "theirs" }
    if i == 119usize { ret "them" }
    if i == 120usize { ret "themselves" }
    if i == 121usize { ret "then" }
    if i == 122usize { ret "there" }
    if i == 123usize { ret "there's" }
    if i == 124usize { ret "these" }
    if i == 125usize { ret "they" }
    if i == 126usize { ret "they'd" }
    if i == 127usize { ret "they'll" }
    if i == 128usize { ret "they're" }
    if i == 129usize { ret "they've" }
    if i == 130usize { ret "this" }
    if i == 131usize { ret "those" }
    if i == 132usize { ret "through" }
    if i == 133usize { ret "to" }
    if i == 134usize { ret "too" }
    if i == 135usize { ret "under" }
    if i == 136usize { ret "until" }
    if i == 137usize { ret "up" }
    if i == 138usize { ret "very" }
    if i == 139usize { ret "was" }
    if i == 140usize { ret "wasn't" }
    if i == 141usize { ret "we" }
    if i == 142usize { ret "we'd" }
    if i == 143usize { ret "we'll" }
    if i == 144usize { ret "we're" }
    if i == 145usize { ret "we've" }
    if i == 146usize { ret "were" }
    if i == 147usize { ret "weren't" }
    if i == 148usize { ret "what" }
    if i == 149usize { ret "what's" }
    if i == 150usize { ret "when" }
    if i == 151usize { ret "when's" }
    if i == 152usize { ret "where" }
    if i == 153usize { ret "where's" }
    if i == 154usize { ret "which" }
    if i == 155usize { ret "while" }
    if i == 156usize { ret "who" }
    if i == 157usize { ret "who's" }
    if i == 158usize { ret "whom" }
    if i == 159usize { ret "why" }
    if i == 160usize { ret "why's" }
    if i == 161usize { ret "with" }
    if i == 162usize { ret "won't" }
    if i == 163usize { ret "would" }
    if i == 164usize { ret "wouldn't" }
    if i == 165usize { ret "you" }
    if i == 166usize { ret "you'd" }
    if i == 167usize { ret "you'll" }
    if i == 168usize { ret "you're" }
    if i == 169usize { ret "you've" }
    if i == 170usize { ret "your" }
    if i == 171usize { ret "yours" }
    if i == 172usize { ret "yourself" }
    if i == 173usize { ret "yourselves" }
    ret ""
}

fn is_stopword_en(w: str) -> bool {
    var lo = 0usize
    var hi = STOP_EN_N
    while lo < hi {
        let mid = (lo + hi) / 2usize
        let c = str.compare(stop_en_at(mid), w)
        if c == 0i32 { ret true }
        if c < 0i32 { lo = mid + 1usize } else { hi = mid }
    }
    ret false
}

// tm removePunctuation(x): gsub("[[:punct:]]+", "", x) for ASCII text, the characters ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~ removed
fn is_ascii_punct(b: u8) -> bool {
    ret (b >= 33u8 && b <= 47u8) || (b >= 58u8 && b <= 64u8) || (b >= 91u8 && b <= 96u8) || (b >= 123u8 && b <= 126u8)
}

fn remove_punctuation(a: *mem.Arena, s: str) -> (str, err) {
    let (bld, eb) = str.builder(a, s.len + 1usize)
    if eb != ok { ret ("", eb) }
    var bd = bld
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if !is_ascii_punct(c) {
            let e = str.push_byte(&bd, c)
            if e != ok { ret ("", e) }
        }
        i += 1usize
    }
    ret (str.done(&bd), ok)
}
