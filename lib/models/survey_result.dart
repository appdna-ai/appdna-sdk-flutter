/// Represents the result of a completed or dismissed survey.
class SurveyResult {
  /// The survey ID.
  final String surveyId;

  /// Whether the survey was completed (true) or dismissed (false).
  final bool completed;

  /// Number of questions answered.
  final int questionsAnswered;

  /// Survey answers (only present when completed).
  final List<SurveyAnswer>? answers;

  const SurveyResult({
    required this.surveyId,
    required this.completed,
    required this.questionsAnswered,
    this.answers,
  });

  factory SurveyResult.fromMap(Map<String, dynamic> map) {
    return SurveyResult(
      surveyId: map['surveyId'] as String? ?? '',
      completed: map['completed'] as bool? ?? false,
      questionsAnswered: map['questionsAnswered'] as int? ?? 0,
      answers: (map['answers'] as List<dynamic>?)
          ?.map((a) => SurveyAnswer.fromMap(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'surveyId': surveyId,
        'completed': completed,
        'questionsAnswered': questionsAnswered,
        if (answers != null) 'answers': answers!.map((a) => a.toMap()).toList(),
      };
}

/// A single survey answer.
class SurveyAnswer {
  /// The question ID.
  final String questionId;

  /// The answer value (can be int, String, List, etc.).
  final dynamic answer;

  const SurveyAnswer({required this.questionId, required this.answer});

  factory SurveyAnswer.fromMap(Map<String, dynamic> map) {
    // SPEC-070-C — the survey delegate emits camelCase `questionId` (matching
    // the native forwarder). Read/write camelCase so this public model stays
    // consistent with the runtime shape.
    return SurveyAnswer(
      questionId: map['questionId'] as String? ?? '',
      answer: map['answer'],
    );
  }

  Map<String, dynamic> toMap() => {
        'questionId': questionId,
        'answer': answer,
      };
}
