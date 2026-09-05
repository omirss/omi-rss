import type { ComponentChildren } from "preact";
import type { ArticleListItem } from "../../lib/api-types.js";
import { ArticleRow } from "./ArticleRow.js";
import "./reading.css";

export interface ArticleListProps {
  articles: ArticleListItem[];
  onOpen: (index: number) => void;
  onToggleStar: (article: ArticleListItem) => void;
  showSnippet?: boolean;
  footer?: ComponentChildren;
}

export function ArticleList({ articles, onOpen, onToggleStar, showSnippet, footer }: ArticleListProps) {
  return (
    <div class="article-list">
      {articles.map((article, index) => (
        <ArticleRow
          key={article.id}
          article={article}
          index={index}
          onOpen={(_, rowIndex) => onOpen(rowIndex)}
          onToggleStar={onToggleStar}
          showSnippet={showSnippet}
        />
      ))}
      {footer}
    </div>
  );
}
