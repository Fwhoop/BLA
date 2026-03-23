class Question {
  final String question;
  final String answer;

  Question({
    required this.question,
    required this.answer,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        question: json['question'] ?? '',
        answer: json['answer'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
      };
}

class Category {
  final String name;
  final List<Question> questions;

  Category({
    required this.name,
    required this.questions,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        name: json['name'] ?? '',
        questions: (json['questions'] as List<dynamic>?)
                ?.map((q) => Question.fromJson(q as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'questions': questions.map((q) => q.toJson()).toList(),
      };
}

class FaqData {
  final List<Category> categories;

  FaqData({
    required this.categories,
  });

  factory FaqData.fromJson(Map<String, dynamic> json) => FaqData(
        categories: (json['categories'] as List<dynamic>?)
                ?.map((c) => Category.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'categories': categories.map((c) => c.toJson()).toList(),
      };
}

