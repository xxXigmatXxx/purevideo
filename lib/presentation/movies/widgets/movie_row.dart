import 'package:flutter/material.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';

class MovieRow extends StatelessWidget {
  final String title;
  final List<MovieModel> movies;

  const MovieRow({
    super.key,
    required this.title,
    required this.movies,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return Padding(
                padding: const EdgeInsets.all(4.0),
                child: SizedBox(
                  width: 132,
                  child: TvFocusable(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context.pushNamed(
                        'movie_details_plain',
                        extra: movie,
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PosterImage(
                        url: movie.imageUrl,
                        headers: movie.imageHeaders,
                        fallbacks: movie.fallbackPosterCandidates,
                        title: movie.title,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
