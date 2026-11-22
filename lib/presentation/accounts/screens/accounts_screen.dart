import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/utils/supported_enum.dart';
import 'package:purevideo/data/models/movie_model.dart';
import 'package:purevideo/presentation/accounts/bloc/accounts_bloc.dart';
import 'package:purevideo/presentation/accounts/bloc/accounts_event.dart';
import 'package:purevideo/presentation/accounts/bloc/accounts_state.dart';
import 'package:purevideo/presentation/global/widgets/error_view.dart';
import 'package:purevideo/presentation/global/widgets/poster_image.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static const _activeServices = [
    SupportedService.filman,
    SupportedService.obejrzyjto,
    SupportedService.ekino,
    SupportedService.docchi,
    SupportedService.bajeczki,
  ];

  Widget _buildServiceLogo(SupportedService service) {
    return SizedBox(
      width: 40,
      height: 32,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: PosterImage(
          url: service.image,
          headers: MovieModel.buildImageHeaders(service, service.image),
          title: service.displayName,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          decodeWidth: 160,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Konta')),
      body: BlocBuilder<AccountsBloc, AccountsState>(
        builder: (context, state) {
          final visibleAccounts = Map.fromEntries(
            state.accounts.entries.where((e) => !e.key.isExtraSource),
          );

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _activeServices.length,
                    itemBuilder: (context, index) {
                      final service = _activeServices[index];
                      final isLoggedIn = visibleAccounts.containsKey(service);
                      if (isLoggedIn) {
                        return const SizedBox.shrink();
                      }
                      final isPasswordless =
                          service.loginRequiredFields.isEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TvFocusable(
                          borderRadius: BorderRadius.circular(12),
                          focusScale: 1.01,
                          onTap: () {
                            if (isPasswordless) {
                              context.read<AccountsBloc>().add(
                                    SignInRequested(
                                      service: service,
                                      fields: const {'anonymous': 'true'},
                                    ),
                                  );
                            } else {
                              context.pushNamed(
                                'login',
                                pathParameters: {'service': service.name},
                              );
                            }
                          },
                          child: Card(
                            child: ListTile(
                              leading: _buildServiceLogo(service),
                              title: Text(service.displayName),
                              subtitle: isPasswordless
                                  ? const Text(
                                      'Dostęp publiczny • dotknij aby włączyć (bez hasła)',
                                      style: TextStyle(fontSize: 12),
                                    )
                                  : null,
                              trailing: Icon(
                                isPasswordless
                                    ? Icons.power_settings_new
                                    : Icons.login,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      if (state is AccountsLoading) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (state is AccountsError) {
                        return ErrorView(
                          message: state.message,
                          onRetry: () {
                            context.read<AccountsBloc>().add(
                                  const LoadAccountsRequested(),
                                );
                          },
                        );
                      }

                      if (state is AccountsLoaded) {
                        if (visibleAccounts.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Brak aktywnych kont. Dodaj lub włącz źródło powyżej.',
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: visibleAccounts.entries.map((account) {
                            final service = account.key;
                            final isPasswordless =
                                service.loginRequiredFields.isEmpty;
                            final loginLabel = account.value.fields.entries
                                .firstWhere(
                                  (element) =>
                                      element.key == 'login' ||
                                      element.key == 'email',
                                  orElse: () => MapEntry(
                                    'login',
                                    isPasswordless
                                        ? 'Dostęp publiczny'
                                        : 'Gość',
                                  ),
                                )
                                .value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: _buildServiceLogo(service),
                                title: Text(loginLabel),
                                subtitle: Text(service.displayName),
                                trailing: IconButton(
                                  icon: Icon(
                                    isPasswordless
                                        ? Icons.visibility_off_outlined
                                        : Icons.delete,
                                  ),
                                  tooltip: isPasswordless
                                      ? 'Wyłącz źródło'
                                      : 'Wyloguj',
                                  onPressed: () {
                                    context.read<AccountsBloc>().add(
                                          SignOutRequested(service),
                                        );
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      }

                      return const Center(
                        child: Text('Nieoczekiwany błąd. Spróbuj ponownie.'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
