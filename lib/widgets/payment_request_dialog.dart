import 'package:breez/widgets/amount_form_field.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:breez/bloc/account/account_bloc.dart';
import 'package:breez/bloc/invoice/invoice_model.dart';
import 'package:breez/theme_data.dart' as theme;
import 'package:flutter_advanced_networkimage/provider.dart';
import 'package:image/image.dart' as DartImage;
import 'package:breez/bloc/account/account_model.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:breez/bloc/account/account_actions.dart';
import 'package:breez/widgets/loader.dart';
import 'package:breez/widgets/payment_failed_report_dialog.dart';
import 'package:breez/widgets/payment_confirmation_dialog.dart';
import 'package:breez/widgets/processsing_payment_dialog.dart';
import 'package:breez/widgets/collapse_animation_dialog.dart';
import 'package:breez/widgets/flushbar.dart';
import 'dart:async';

const PAYMENT_LIST_ITEM_HEIGHT = 72.0;
enum PaymentRequestState { PAYMENT_REQUEST, WAITING_FOR_CONFIRMATION, PROCESSING_PAYMENT}

class PaymentRequestDialog extends StatefulWidget {
  final BuildContext context;
  final AccountBloc accountBloc;
  final PaymentRequestModel invoice;
  final GlobalKey firstPaymentItemKey;
  final ScrollController scrollController;
  final _transparentImage = DartImage.encodePng(DartImage.Image(300, 300));

  PaymentRequestDialog(this.context, this.accountBloc, this.invoice, this.firstPaymentItemKey, this.scrollController);

  @override
  State<StatefulWidget> createState() {
    return PaymentRequestDialogState();
  }
}

class PaymentRequestDialogState extends State<PaymentRequestDialog>
    with SingleTickerProviderStateMixin {
  final _dialogKey = GlobalKey();
  final _formKey = GlobalKey<FormState>();
  TextEditingController _invoiceAmountController = new TextEditingController();

  AnimationController controller;
  Animation<double> opacityAnimation;
  Animation<double> borderAnimation;
  Animation<RelativeRect> transitionAnimation;
  Animation<Color> colorAnimation;

  PaymentRequestState _state;

  AccountSettings _accountSettings;
  StreamSubscription<AccountModel> _paymentInProgressSubscription;
  StreamSubscription<AccountSettings> _accountSettingsSubscription;
  StreamSubscription<String> _sentPaymentResultSubscription;

  Int64 _amountToPay;
  String _amountToPayStr;

  bool _inProgress = false;

  double _initialDialogSize;

  @override
  void initState() {
    super.initState();
    _state = PaymentRequestState.PAYMENT_REQUEST;
    _paymentInProgressSubscription = widget.accountBloc.accountStream.listen((acc) {
      _inProgress = acc.paymentRequestInProgress != null && acc.paymentRequestInProgress.isNotEmpty;
    });
    _listenPaymentsResults();
    _invoiceAmountController.addListener(() {
      setState(() {});
    });

  }

  @override
  dispose() {
    _paymentInProgressSubscription?.cancel();
    _accountSettingsSubscription?.cancel();
    _sentPaymentResultSubscription?.cancel();
    controller?.dispose();
    super.dispose();
  }

  _listenPaymentsResults() {
    _accountSettingsSubscription = widget.accountBloc.accountSettingsStream
        .listen((settings) => _accountSettings = settings);

    _sentPaymentResultSubscription = widget.accountBloc.fulfilledPayments.listen((fulfilledPayment) {
      controller = AnimationController(
          vsync: this, duration: Duration(milliseconds: 500));
      borderAnimation = Tween<double>(begin: 0.0, end: 8.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.ease));
      opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: Curves.ease));
      colorAnimation = new ColorTween(
        begin: theme.BreezColors.blue[500],
        end: theme.BreezColors.white[500],
      ).animate(controller)
        ..addListener(() {
          setState(() {});
        });
      controller.addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          Navigator.pop(context);
        }
      });

      Future scrollAnimationFuture = Future.value(null);
      if (widget.scrollController.hasClients) {
        scrollAnimationFuture = widget.scrollController.animateTo(
            widget.scrollController.position.minScrollExtent,
            duration: Duration(milliseconds: 200), curve: Curves.ease)
            .whenComplete(() => Future.delayed(Duration(milliseconds: 50)));
      }

      scrollAnimationFuture.whenComplete(() {
        _initializeTransitionAnimation();
        controller.value = 1.0;
        // Trigger the collapse animation and show flushbar after the animation is completed
        controller.reverse().whenComplete(() =>
            showFlushbar(context, message: "Payment was successfuly sent!"));
      });
    }, onError: (err) => _onPaymentError(_accountSettings, err as PaymentError));
  }

  void _initializeTransitionAnimation() {
    double _dialogYMargin = (MediaQuery.of(context).size.height - MediaQuery.of(widget.context).padding.top - _initialDialogSize) / 2;
    RenderBox _paymentTableBox = widget.firstPaymentItemKey.currentContext.findRenderObject();
    var _paymentItemStartPosition = _paymentTableBox.localToGlobal(Offset.zero).dy - MediaQuery.of(widget.context).padding.top;
    var _paymentItemEndPosition = (MediaQuery.of(context).size.height - MediaQuery.of(widget.context).padding.top - _paymentItemStartPosition) - PAYMENT_LIST_ITEM_HEIGHT;
    var tween = new RelativeRectTween(
        begin: new RelativeRect.fromLTRB(0.0, _paymentItemStartPosition, 0.0, _paymentItemEndPosition),
        end: new RelativeRect.fromLTRB(32.0, _dialogYMargin, 32.0, _dialogYMargin));
    transitionAnimation = tween.animate(controller);
  }

  _onPaymentError(AccountSettings accountSettings, PaymentError error) async {
    bool prompt =
        accountSettings.failePaymentBehavior == BugReportBehavior.PROMPT;
    bool send =
        accountSettings.failePaymentBehavior == BugReportBehavior.SEND_REPORT;

    // Close Payment Request Dialog
    Navigator.pop(context);
    showFlushbar(context,
        message:
        "Failed to send payment: ${error
            .toString()
            .split("\n")
            .first}");

    if (!error.validationError) {
      if (prompt) {
        send = await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) =>
            new PaymentFailedReportDialog(context, widget.accountBloc));
      }

      if (send) {
        var sendAction = SendPaymentFailureReport(error.traceReport);
        widget.accountBloc.userActionsSink.add(sendAction);
        await Navigator.push(
            context,
            createLoaderRoute(context,
                message: "Sending Report...",
                opacity: 0.8,
                action: sendAction.future));
      }
    }
  }

  // Do not pop dialog if there's a payment being processed
  Future<bool> _onWillPop() async {
    if (_inProgress) {
      return false;
    }
    return true;
  }

  void _onStateChange(PaymentRequestState state) {
    setState(() {
      _state = state;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(onWillPop: _onWillPop,
        child: showPaymentRequestDialog());
  }

  Widget showPaymentRequestDialog() {
    var _dialogContent;
    if(_state == PaymentRequestState.PAYMENT_REQUEST) {
      _dialogContent = _buildPaymentRequestDialog();
    } else if (_state == PaymentRequestState.WAITING_FOR_CONFIRMATION) {
      _dialogContent = PaymentConfirmationDialog(context, widget.accountBloc, widget.invoice, _amountToPay, _amountToPayStr, (state) => _onStateChange(state));
    } else if (_state == PaymentRequestState.PROCESSING_PAYMENT) {
      _dialogContent = ProcessingPaymentDialog(context);
    }

    return controller == null
        ? _buildDialog(_dialogContent)
        : CollapseAnimationDialog(context, transitionAnimation, colorAnimation, borderAnimation, opacityAnimation, _initialDialogSize, _dialogContent);
  }

  Widget _buildPaymentRequestContent() {
    return StreamBuilder<AccountModel>(
      stream: widget.accountBloc.accountStream,
      builder: (context, snapshot) {
        var account = snapshot.data;
        if (account == null) {
          return new Container(width: 0.0, height: 0.0);
        }
        List<Widget> children = [];
        _addIfNotNull(children, _buildPayeeNameWidget());
        _addIfNotNull(children, _buildRequestPayTextWidget());
        _addIfNotNull(children, _buildAmountWidget(account));
        _addIfNotNull(children, _buildDescriptionWidget());
        _addIfNotNull(children, _buildErrorMessage(account));
        _addIfNotNull(children, _buildActions(account));

        return Container(
          width: MediaQuery
              .of(context)
              .size
              .width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildPaymentRequestTitle() {
    return widget.invoice.payeeImageURL.isEmpty
        ? null
        : Stack(
      children: <Widget>[
        Center(
            child: CircularProgressIndicator(
              valueColor: new AlwaysStoppedAnimation<Color>(
                theme.BreezColors.blue[500],
              ),
            )),
        Center(
            child: ClipOval(
              child: FadeInImage(
                  width: 64.0,
                  height: 64.0,
                  placeholder: MemoryImage(widget._transparentImage),
                  image: AdvancedNetworkImage(widget.invoice.payeeImageURL,
                      useDiskCache: true),
                  fadeOutDuration: new Duration(milliseconds: 200),
                  fadeInDuration: new Duration(milliseconds: 200)),
            )),
      ],
    );
  }

  void _addIfNotNull(List<Widget> widgets, Widget w) {
    if (w != null) {
      widgets.add(w);
    }
  }

  Widget _buildPayeeNameWidget() {
    return widget.invoice.payeeName == null
        ? null
        : Text(
            "${widget.invoice.payeeName}",
            style: theme.paymentRequestTitleStyle,
            textAlign: TextAlign.center,
          );
  }

  Widget _buildErrorMessage(AccountModel account) {
    String validationError = account.validateOutgoingPayment(amountToPay(account));
    if (validationError == null || widget.invoice.amount == 0) {
      return null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
      child: AutoSizeText(validationError,
          maxLines: 3,
          textAlign: TextAlign.center,
          style: theme.paymentRequestSubtitleStyle.copyWith(color: Colors.red)),
    );
  }

  Widget _buildRequestPayTextWidget() {
    return widget.invoice.payeeName == null || widget.invoice.payeeName.isEmpty
        ? new Text(
            "You are requested to pay:",
            style: theme.paymentRequestSubtitleStyle,
            textAlign: TextAlign.center,
          )
        : new Text(
            "is requesting you to pay:",
            style: theme.paymentRequestSubtitleStyle,
            textAlign: TextAlign.center,
          );
  }

  Widget _buildAmountWidget(AccountModel account) {
    if (widget.invoice.amount == 0) {
      return Theme(
        data: Theme.of(context).copyWith(
          hintColor: theme.alertStyle.color,
          accentColor: theme.BreezColors.blue[500],
          primaryColor: theme.BreezColors.blue[500],
          errorColor: Colors.red),
          child: Form(
            autovalidate: true,
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0),
              child: Container(
                height: 80.0,
                child: AmountFormField(
                  style: theme.alertStyle.copyWith(height: 1.0),
                  validatorFn: account.validateOutgoingPayment,
                  currency: account.currency,
                  controller: _invoiceAmountController,
                  decoration: new InputDecoration(
                      labelText: account.currency.displayName +
                          " Amount"),
                ),
              ),
            ),
        ),
      );
    }
    return Text(
      account.currency.format(widget.invoice.amount),
      style: theme.paymentRequestAmountStyle,
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescriptionWidget() {
    return widget.invoice.description == null || widget.invoice.description.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
            child: AutoSizeText(
              widget.invoice.description,
              style: theme.paymentRequestSubtitleStyle,
              textAlign: widget.invoice.description.length > 40
                  ? TextAlign.justify
                  : TextAlign.center,
              maxLines: 3,
            ),
          );
  }
  void _getDialogSize() {
    RenderBox _dialogBox = _dialogKey.currentContext.findRenderObject();
    _initialDialogSize = _dialogBox.size.height;
  }

  Widget _buildActions(AccountModel account) {
    List<Widget> actions = [
      SimpleDialogOption(
        onPressed: () => Navigator.pop(context),
        child: new Text("CANCEL", style: theme.buttonStyle),
      )
    ];

    Int64 toPay = amountToPay(account);
    if (toPay > 0 && account.maxAllowedToPay >= toPay) {
      actions.add(SimpleDialogOption(
        onPressed: (() async {
          if (widget.invoice.amount > 0 || _formKey.currentState.validate()) {
            _getDialogSize();
            if (widget.invoice.amount == 0) {
              setState(() {
                _state = PaymentRequestState.WAITING_FOR_CONFIRMATION;
                _amountToPay = toPay;
                _amountToPayStr = account.currency.format(amountToPay(account));
              });
            } else {
              widget.accountBloc.sentPaymentsSink.add(
                  PayRequest(widget.invoice.rawPayReq, amountToPay(account)));
              setState(() {
                _state = PaymentRequestState.PROCESSING_PAYMENT;
              });
            }
          }
        }),
        child: new Text("APPROVE", style: theme.buttonStyle),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions,
      ),
    );
  }

  Int64 amountToPay(AccountModel acc) {
    Int64 amount = widget.invoice.amount;
    if (amount == 0) {
      try {
        amount = acc.currency.parse(_invoiceAmountController.text);
      } catch (e) {}
    }
    return amount;
  }

  Widget _buildPaymentRequestDialog() {
    List<Widget> _paymentRequestDialog = <Widget>[];
    Widget _title;
    if (_buildPaymentRequestTitle() != null) {
      _title = Container(
        height: (widget.invoice.payeeImageURL.isNotEmpty) ? 128.0 : 64.0,
        padding: widget.invoice.payeeImageURL.isEmpty ? EdgeInsets.zero : EdgeInsets.only(top: 48.0),
        child: _buildPaymentRequestTitle(),
      );
    }
    Widget _content =
    Padding(
      padding: EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 16.0),
      child: _buildPaymentRequestContent(),
    );
    _addIfNotNull(_paymentRequestDialog, _title);
    _addIfNotNull(_paymentRequestDialog, _content);
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: _paymentRequestDialog);
  }

  Widget _buildDialog(Widget content) {
    return Dialog(
        child: Container(
            key: _dialogKey,
            constraints: BoxConstraints(minHeight: 220.0, maxHeight: 320.0),
            height: _initialDialogSize,
            width: MediaQuery.of(context).size.width,
            child: content),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0)));
  }
}
