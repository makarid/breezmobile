import 'dart:async';

import 'package:breez/bloc/account/account_bloc.dart';
import 'package:breez/bloc/account/account_model.dart';
import 'package:breez/bloc/invoice/invoice_bloc.dart';
import 'package:breez/bloc/lnurl/lnurl_actions.dart';
import 'package:breez/bloc/lnurl/lnurl_bloc.dart';
import 'package:breez/theme_data.dart' as theme;
import 'package:breez/widgets/flushbar.dart';
import 'package:breez/widgets/loading_animated_text.dart';
import 'package:flutter/material.dart';

import '../sync_progress_dialog.dart';

class LNURlWithdrawDialog extends StatefulWidget {
  final InvoiceBloc invoiceBloc;
  final AccountBloc accountBloc;
  final LNUrlBloc lnurlBloc;

  const LNURlWithdrawDialog(this.invoiceBloc, this.accountBloc, this.lnurlBloc);

  @override
  State<StatefulWidget> createState() {
    return LNUrlWithdrawDialogState();
  }
}

class LNUrlWithdrawDialogState extends State<LNURlWithdrawDialog>
    with SingleTickerProviderStateMixin {
  String _error;
  Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    var controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: 1000));
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: controller, curve: Curves.ease));
    controller.value = 1.0;
    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && this.mounted) {
        Navigator.pop(context, true);
      }
    });

    widget.invoiceBloc.readyInvoicesStream.first.then((bolt11) {
      return widget.accountBloc.accountStream
          .firstWhere((a) => a != null && a.syncedToChain == true)
          .then((_) {
        if (this.mounted) {
          Withdraw withdrawAction = Withdraw(bolt11);
          widget.lnurlBloc.actionsSink.add(withdrawAction);
          _listenPaidInvoice(bolt11, controller);
          return withdrawAction.future;
        }
        return null;
      });
    }).catchError((err) {
      setState(() {
        _error = err.toString();
      });
    });
  }

  void _listenPaidInvoice(String bolt11, AnimationController controller) async {
    var payreq = await widget.invoiceBloc.paidInvoicesStream
        .firstWhere((payreq) {
          bool ok = payreq == bolt11;
          return ok;
        }, orElse: () => null);
        if (payreq != null) {
          Timer(Duration(milliseconds: 1000), () {
                if (this.mounted) {
                  controller.reverse();
                }
              });
        }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: AlertDialog(
        title: Text("Receive Funds",
            style: Theme.of(context).dialogTheme.titleTextStyle,
            textAlign: TextAlign.center),
        content: StreamBuilder<AccountModel>(
            stream: widget.accountBloc.accountStream,
            builder: (context, snapshot) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _error != null
                      ? Text("Failed to receive funds: $_error",
                          style: Theme.of(context).dialogTheme.contentTextStyle,
                          textAlign: TextAlign.center)
                      : snapshot.hasData && snapshot.data.syncedToChain != true
                          ? SizedBox()
                          : LoadingAnimatedText(
                              'Please wait while your payment is being processed',
                              textStyle: Theme.of(context)
                                  .dialogTheme
                                  .contentTextStyle,
                              textAlign: TextAlign.center,
                            ),
                  _error != null
                      ? SizedBox(height: 16.0)
                      : snapshot.hasData && snapshot.data.syncedToChain != true
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: SyncProgressDialog(closeOnSync: false),
                            )
                          : Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Image.asset(
                                theme.customData[theme.themeId].loaderAssetPath,
                                gaplessPlayback: true,
                              )),
                  FlatButton(
                    onPressed: (() {
                      Navigator.pop(context, false);
                    }),
                    child: Text("CLOSE",
                        style: Theme.of(context).primaryTextTheme.button),
                  )
                ],
              );
            }),
      ),
    );
  }
}
