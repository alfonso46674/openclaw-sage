"""Unit tests for scripts/bm25_search.py"""
import sys
import os
import math

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from bm25_search import (
    tokenize, build_meta, bm25_score, find_best_excerpt, MIN_DOCS_FOR_IDF
)


class TestTokenize:
    def test_basic(self):
        assert tokenize("hello world") == ["hello", "world"]

    def test_lowercase(self):
        assert tokenize("Hello World") == ["hello", "world"]

    def test_numbers(self):
        assert tokenize("foo123 bar") == ["foo123", "bar"]

    def test_punctuation_stripped(self):
        assert tokenize("foo-bar, baz.") == ["foo", "bar", "baz"]

    def test_empty(self):
        assert tokenize("") == []

    def test_whitespace_only(self):
        assert tokenize("   ") == []

    def test_multi_word_query(self):
        assert tokenize("webhook retry") == ["webhook", "retry"]


class TestBuildMeta:
    def test_num_docs(self):
        docs = {"a": ["hello world"], "b": ["foo bar"]}
        meta = build_meta(docs)
        assert meta["num_docs"] == 2

    def test_df_counts_docs_not_occurrences(self):
        # "hello" appears twice in doc "a" but df should be 1
        docs = {"a": ["hello hello world"]}
        meta = build_meta(docs)
        assert meta["df"]["hello"] == 1

    def test_df_across_docs(self):
        docs = {"a": ["hello world"], "b": ["hello there"]}
        meta = build_meta(docs)
        assert meta["df"]["hello"] == 2
        assert meta["df"]["world"] == 1

    def test_avg_dl(self):
        docs = {"a": ["one two"], "b": ["one two three four"]}
        meta = build_meta(docs)
        # doc a: 2 tokens, doc b: 4 tokens, avg = 3
        assert meta["avg_dl"] == 3.0

    def test_doc_lengths(self):
        docs = {"a": ["one two three"]}
        meta = build_meta(docs)
        assert meta["doc_lengths"]["a"] == 3

    def test_empty_corpus(self):
        meta = build_meta({})
        assert meta["num_docs"] == 0
        assert meta["avg_dl"] == 0


class TestBM25Score:
    def test_zero_for_missing_term(self):
        score = bm25_score(["missing"], ["hello", "world"], 2, 2.0, {"hello": 1}, 10)
        assert score == 0.0

    def test_positive_for_matching_term(self):
        score = bm25_score(["hello"], ["hello", "world"], 2, 2.0, {"hello": 1}, 10)
        assert score > 0.0

    def test_higher_tf_increases_score(self):
        df = {"hello": 1}
        score_one = bm25_score(["hello"], ["hello", "world"], 2, 2.0, df, 10)
        score_two = bm25_score(["hello"], ["hello", "hello", "world"], 3, 3.0, df, 10)
        assert score_two > score_one

    def test_multi_term_sums_scores(self):
        df = {"hello": 1, "world": 1}
        score_one = bm25_score(["hello"], ["hello", "world"], 2, 2.0, df, 10)
        score_both = bm25_score(["hello", "world"], ["hello", "world"], 2, 2.0, df, 10)
        assert score_both > score_one

    def test_small_corpus_uses_idf_fallback(self):
        # num_docs < MIN_DOCS_FOR_IDF → idf = 1.0, score still positive
        df = {"hello": 1}
        score = bm25_score(["hello"], ["hello"], 1, 1.0, df, MIN_DOCS_FOR_IDF - 1)
        assert score > 0.0

    def test_rare_term_scores_higher_than_common(self):
        # "rare" in 1 out of 20 docs vs "common" in 18 out of 20
        df = {"rare": 1, "common": 18}
        score_rare = bm25_score(["rare"], ["rare"], 1, 1.0, df, 20)
        score_common = bm25_score(["common"], ["common"], 1, 1.0, df, 20)
        assert score_rare > score_common


class TestFindBestExcerpt:
    def test_selects_line_with_most_query_terms(self):
        lines = ["foo bar", "foo bar baz", "something else"]
        result = find_best_excerpt(lines, ["foo", "bar", "baz"])
        assert result == "foo bar baz"

    def test_fallback_to_first_line_when_no_match(self):
        lines = ["first line", "second line"]
        result = find_best_excerpt(lines, ["nomatch"])
        assert result == "first line"

    def test_truncates_long_lines(self):
        lines = ["x" * 200]
        result = find_best_excerpt(lines, ["x"])
        assert len(result) <= 123  # MAX_EXCERPT_LEN=120 + 3 for "..."
        assert result.endswith("...")

    def test_empty_lines_returns_empty(self):
        result = find_best_excerpt([], ["foo"])
        assert result == ""

    def test_strips_whitespace(self):
        lines = ["  hello world  "]
        result = find_best_excerpt(lines, ["hello"])
        assert result == "hello world"
